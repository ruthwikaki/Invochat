
'use server';
/**
 * @fileoverview Implements the advanced, multi-agent AI chat system for InvoChat.
 * This system uses a Chain-of-Thought approach with distinct steps for planning,
 * generation, validation, and response formulation to provide more accurate and
 * context-aware answers.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { UniversalChatInput, UniversalChatOutput } from '@/types/ai-schemas';
import { UniversalChatInputSchema, UniversalChatOutputSchema } from '@/types/ai-schemas';
import { getSettings } from '@/services/database';
import { config } from '@/config/app-config';
import { logger } from '@/lib/logger';
import { getEconomicIndicators } from './economic-tool';
import { getReorderSuggestions } from './reorder-tool';
import { getSupplierAnalysisTool } from './analyze-supplier-flow';
import { getDeadStockReport } from './dead-stock-tool';
import { getInventoryTurnoverReport } from './inventory-turnover-tool';
import { getDemandForecast, getAbcAnalysis, getGrossMarginAnalysis, getNetMarginByChannel, getMarginTrends, getSalesVelocity, getPromotionalImpactAnalysis } from './analytics-tools';
import { logError, getErrorMessage } from '@/lib/error-handler';
import { getBundleSuggestions } from './suggest-bundles-flow';
import { getPriceOptimizationSuggestions } from './price-optimization-flow';
import { getMarkdownSuggestions } from './markdown-optimizer-flow';
import { findHiddenMoney } from './hidden-money-finder-flow';
import { isRedisEnabled, redisClient } from '@/lib/redis';
import crypto from 'crypto';

// SECURITY FIX (#81): Prevent AI recursion.
// This list of tools is carefully curated to only include data retrieval and analysis tools.
// It EXCLUDES any tool that is a wrapper around another AI flow (like findHiddenMoney, getSupplierAnalysisTool, etc.).
// This prevents the main chat agent from calling other agents, which could lead to infinite loops and high costs.
const safeToolsForOrchestrator = [
    getEconomicIndicators, 
    getReorderSuggestions, 
    getDeadStockReport, 
    getInventoryTurnoverReport,
    getDemandForecast,
    getAbcAnalysis,
    getGrossMarginAnalysis,
    getNetMarginByChannel,
    getMarginTrends,
    getSalesVelocity,
    getPromotionalImpactAnalysis,
    // The following tools are wrappers around AI flows and are EXCLUDED to prevent recursion.
    // getSupplierAnalysisTool, 
    // getBundleSuggestions,
    // getPriceOptimizationSuggestions,
    // getMarkdownSuggestions,
    // findHiddenMoney,
];


const FinalResponseObjectSchema = UniversalChatOutputSchema.omit({ data: true, toolName: true });
const finalResponsePrompt = ai.definePrompt({
  name: 'finalResponsePrompt',
  inputSchema: z.object({ userQuery: z.string(), toolResult: z.any() }),
  outputSchema: FinalResponseObjectSchema,
  prompt: `
    You are an expert AI inventory analyst for the InvoChat application. Your tone is professional, intelligent, and helpful.
    The user asked: "{{userQuery}}"
    You have executed a tool and received this JSON data as a result:
    {{{json toolResult}}}

    **YOUR TASK:**
    Your goal is to synthesize this raw data into a clear, concise, and actionable response for the user. Do NOT just repeat the data. Provide insight.

    **RESPONSE GUIDELINES:**

    1.  **Analyze & Synthesize**:
        - **If the data has an 'analysis' field:** Use that text as your primary response. This means another AI has already summarized the data for you.
        - **If data exists (but no 'analysis' field):** Briefly summarize the key finding. Don't just list the data. For example, instead of saying "The data shows Vendor A has a 98% on-time rate", say "Vendor A is your most reliable supplier with a 98% on-time delivery rate."
        - **If data is empty or null:** Do not just say "No data found." Instead, provide a helpful and context-aware response. For example, if asked for dead stock and none is found, say "Good news! I didn't find any dead stock based on your current settings. Everything seems to be selling well."

    2.  **Formulate Response Body**:
        - Write a natural language paragraph that answers the user's question.
        - **Crucially, do NOT mention technical details** like "JSON", "database", "API", or the specific tool you used. The user should feel like they are talking to a single, intelligent analyst.

    3.  **Assess Confidence & Assumptions**:
        - **Confidence Score (0.0 to 1.0):** How well does the data answer the user's exact question? A direct answer is 1.0. If you had to make an assumption (e.g., interpreting "best" as "most profitable"), lower the score to ~0.8. If the data is only tangentially related, lower it further.
        - **Assumptions List:** If confidence is below 1.0, state the assumptions you made. E.g., ["Assumed 'best sellers' means by revenue, not units sold."]. If confidence is 1.0, this should be an empty array.

    4.  **Suggest Visualization**:
        - Based on the data's structure, suggest an appropriate visualization.
        - **Available types:** 'table', 'bar', 'pie', 'line', 'treemap', 'scatter', 'none'.
        - Provide a clear and descriptive \`title\` for the visualization.

    5.  **Final Output**:
        - Return a single, valid JSON object that strictly adheres to the output schema, containing 'response', 'visualization', 'confidence', and 'assumptions'.
  `,
});


const universalChatOrchestrator = ai.defineFlow(
  {
    name: 'universalChatOrchestrator',
    inputSchema: UniversalChatInputSchema,
    outputSchema: UniversalChatOutputSchema,
  },
  async (input) => {
    const { companyId, conversationHistory } = input;
    const lastMessage = conversationHistory[conversationHistory.length - 1];
    const userQuery = lastMessage?.content[0]?.text || '';
    
    if (!userQuery) {
        throw new Error("User query was empty.");
    }
    
    // --- Redis Caching Logic ---
    const queryHash = crypto.createHash('sha256').update(userQuery.toLowerCase()).digest('hex');
    const cacheKey = `aichat:${companyId}:${queryHash}`;
    if (isRedisEnabled) {
      try {
        const cachedResponse = await redisClient.get(cacheKey);
        if (cachedResponse) {
          logger.info(`[AI Cache] HIT for query: "${userQuery}"`);
          return JSON.parse(cachedResponse);
        }
        logger.info(`[AI Cache] MISS for query: "${userQuery}"`);
      } catch (e) {
        logError(e, { context: 'Redis cache get failed for AI chat' });
      }
    }
    // --- End Caching Logic ---

    const aiModel = config.ai.model;
    
    try {
        // Step 1: Let the AI decide if a tool is needed.
        // SECURITY FIX (#71): Pass user input in the `prompt` field, not as part of the `system` instruction.
        // This mitigates prompt injection attacks.
        const { toolCalls } = await ai.generate({
          model: aiModel,
          tools: safeToolsForOrchestrator,
          history: conversationHistory.slice(0, -1),
          system: `You are an AI assistant for a business with company ID '${companyId}'. You must use this ID when calling any tool that requires a companyId.`,
          prompt: userQuery, // User input is now properly separated.
          maxOutputTokens: 2048,
        });
        
        // Step 2: If a tool is chosen, execute it.
        if (toolCalls && toolCalls.length > 0) {
            const toolCall = toolCalls[0];
            logger.info(`[UniversalChat:Flow] AI chose to use a tool: ${toolCall.name}`);
            
            try {
                const toolResult = await ai.runTool(toolCall);
                
                // Step 3: Use a second AI call to formulate a natural language response from the tool's data.
                const { output: finalOutput } = await finalResponsePrompt(
                    { userQuery, toolResult: toolResult.output },
                    { model: aiModel, maxOutputTokens: 2048 }
                );

                if (!finalOutput) {
                    throw new Error('The AI model did not return a valid final response object after tool use.');
                }
                
                // If the tool output has its own nested data (like the supplier analysis flow), use that for the visualization.
                const dataForVisualization = toolResult.output.performanceData || toolResult.output;
                
                const responseToCache = {
                    ...finalOutput,
                    data: dataForVisualization,
                    toolName: toolCall.name,
                };
                
                if (isRedisEnabled) {
                    await redisClient.set(cacheKey, JSON.stringify(responseToCache), 'EX', config.redis.ttl.aiQuery);
                }
                return responseToCache;

            } catch (e) {
                logError(e, { context: `Tool execution failed for '${toolCall.name}'` });
                return {
                    response: `I tried to use a tool to answer your question, but it failed. Please try rephrasing your question or check the system status.`,
                    data: [],
                    visualization: { type: 'none', title: '' },
                    confidence: 0.1,
                    assumptions: ['The tool needed to answer your question failed to execute.'],
                    toolName: toolCall.name,
                } as any;
            }
        }

        // Step 4: If no tool is called, the AI should answer directly.
        logger.warn("[UniversalChat:Flow] No tool was called. Answering from general knowledge.");
        const { text } = await ai.generate({
            model: aiModel,
            history: conversationHistory.slice(0, -1),
            prompt: userQuery,
            maxOutputTokens: 1024,
        });

        const responseToCache = {
            response: text,
            data: [],
            visualization: { type: 'none', title: '' },
            confidence: 0.5,
            assumptions: ['I was unable to answer this from your business data and answered from general knowledge.'],
        };
        
        if (isRedisEnabled) {
            await redisClient.set(cacheKey, JSON.stringify(responseToCache), 'EX', config.redis.ttl.aiQuery);
        }
        return responseToCache;

    } catch (e) {
        const errorMessage = getErrorMessage(e);
        logError(e, { context: `Universal Chat Flow failed for query: "${userQuery}"` });

        // Check for specific AI service availability errors
        if (errorMessage.includes('503') || errorMessage.includes('unavailable')) {
             return {
                response: `I'm sorry, but the AI service is currently unavailable. This may be a temporary issue. Please try again in a few moments.`,
                data: [],
                visualization: { type: 'none', title: '' },
                confidence: 0.0,
                assumptions: ['The AI service is unavailable.'],
                isError: true,
            } as any;
        }

        return {
            response: `I'm sorry, but I encountered an unexpected error while trying to generate a response. The AI service may be temporarily unavailable. Please try again in a few moments.`,
            data: [],
            visualization: { type: 'none', title: '' },
            confidence: 0.0,
            assumptions: ['An unexpected error occurred in the AI processing flow.'],
            isError: true, // Custom flag to indicate an error state in the UI
        } as any; // Cast to any to allow the `isError` flag
    }
  }
);

export const universalChatFlow = universalChatOrchestrator;
