
'use server';
/**
 * @fileoverview Implements the advanced, multi-agent AI chat system for ARVO.
 * This system uses a Chain-of-Thought approach with distinct steps for planning,
 * generation, validation, and response formulation to provide more accurate and
 * context-aware answers.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import type { UniversalChatOutput } from '@/types/ai-schemas';
import { UniversalChatInputSchema, UniversalChatOutputSchema } from '@/types/ai-schemas';
import { config } from '@/config/app-config';
import { logger } from '@/lib/logger';
import { getEconomicIndicators } from './economic-tool';
import { getDeadStockReport } from './dead-stock-tool';
import { getInventoryTurnoverReport } from './inventory-turnover-tool';
import { getReorderSuggestions } from './reorder-tool';
import { getSupplierAnalysisTool } from './analyze-supplier-flow';
import { getMarkdownSuggestions } from './markdown-optimizer-flow';
import { getPriceOptimizationSuggestions } from './price-optimization-flow';
import { getBundleSuggestions } from './suggest-bundles-flow';
import { findHiddenMoney } from './hidden-money-finder-flow';
import { getProductDemandForecast } from './product-demand-forecast-flow';
import { getDemandForecast, getAbcAnalysis, getGrossMarginAnalysis, getNetMarginByChannel, getMarginTrends, getSalesVelocity, getPromotionalImpactAnalysis } from './analytics-tools';
import { logError, getErrorMessage } from '@/lib/error-handler';
import { isRedisEnabled, redisClient } from '@/lib/redis';
import crypto from 'crypto';
import type { MessageData } from 'genkit';

// These are the tools that are safe and fully implemented for the AI to use.
const safeToolsForOrchestrator = [
    getReorderSuggestions,
    getDeadStockReport,
    getInventoryTurnoverReport,
    getSupplierAnalysisTool,
    getMarkdownSuggestions,
    getPriceOptimizationSuggestions,
    getBundleSuggestions,
    findHiddenMoney,
    getEconomicIndicators,
    getProductDemandForecast,
    getDemandForecast,
    getAbcAnalysis,
    getGrossMarginAnalysis,
    getNetMarginByChannel,
    getMarginTrends,
    getSalesVelocity,
    getPromotionalImpactAnalysis,
];


const FinalResponseObjectSchema = UniversalChatOutputSchema.omit({ data: true, toolName: true });
const finalResponsePrompt = ai.definePrompt({
  name: 'finalResponsePrompt',
  input: { schema: z.object({ userQuery: z.string(), toolResult: z.any() }) },
  output: { schema: FinalResponseObjectSchema },
  prompt: `
    You are an expert AI inventory analyst for the ARVO application. Your tone is professional, intelligent, and helpful.
    The user asked: "{{userQuery}}"
    The result from your internal tools is:
    {{{json toolResult}}}

    **YOUR TASK:**
    Your goal is to synthesize this information into a clear, concise, and actionable response for the user. Do NOT just repeat the data. Provide insight.

    **RESPONSE GUIDELINES:**

    1.  **Analyze & Synthesize**:
        - **If the result contains an 'analysis' field:** Use that text as your primary response. This means another AI has already summarized the data for you.
        - **If data exists (but no 'analysis' field):** Briefly summarize the key finding. Don't just list the data. For example, instead of saying "The data shows Vendor A has a 98% on-time rate", say "Vendor A is your most reliable supplier with a 98% on-time delivery rate."
        - **If data is empty or null:** Do not just say "No data found." Instead, provide a helpful and context-aware response. For example, if asked for dead stock and none is found, say "Good news! I didn't find any dead stock based on your current settings. Everything seems to be selling well."

    2.  **Formulate Response Body**:
        - Write a natural language paragraph that answers the user's question.
        - **Crucially, do NOT mention technical details** like "JSON", "database", "API", or the specific tool you used. The user should feel like they are talking to a single, intelligent analyst.

    3.  **Assess Confidence & Assumptions**:
        - **Confidence Score (0.0 to 1.0):** How well does the data answer the user's exact question? A direct answer is 1.0. If you had to make an assumption (e.g., interpreting "best" as "most profitable"), lower the score to ~0.8. If the data is only tangentially related, lower it further.
        - **Assumptions List:** If confidence is below 1.0, state the assumptions you made. E.g., ["Assumed 'best sellers' means by revenue, not units sold."]. If confidence is 1.0, this should be an empty array.

    4.  **Suggest Visualization**:
        - Based on the data's structure, suggest an appropriate visualization. Use 'chart' for time-series, categorical comparisons, or distributions. Use 'table' for lists or detailed reports.
        - **Available types:** 'chart', 'table', 'alert', 'none'.
        - Provide a clear and descriptive \`title\` for the visualization.

    5.  **Final Output**:
        - Return a single, valid JSON object that strictly adheres to the output schema, containing 'response', 'visualization', 'confidence', and 'assumptions'.
  `,
});


export const universalChatFlow = ai.defineFlow(
  {
    name: 'universalChatFlow',
    inputSchema: UniversalChatInputSchema,
    outputSchema: UniversalChatOutputSchema,
  },
  async (input) => {
    const { companyId, conversationHistory } = input;
    const userQuery = conversationHistory[conversationHistory.length - 1]?.content[0]?.text || '';

    if (!userQuery) {
        throw new Error("User query was empty.");
    }

    // --- Redis Caching Logic ---
    const queryHash = crypto.createHash('sha256').update(userQuery.toLowerCase().trim()).digest('hex');
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

    try {
        const systemPrompt = {
            role: 'system' as const,
            content: [{ text: `You are an AI assistant for a business. You must use the companyId provided in the tool arguments when calling any tool.`}]
        };

        const genkitHistory = conversationHistory.map(msg => ({
            ...msg,
            role: msg.role === 'assistant' ? 'model' as const : msg.role,
        })) as MessageData[];

        const messages: MessageData[] = [systemPrompt, ...genkitHistory];

        const response = await ai.generate({
          model: config.ai.model,
          tools: safeToolsForOrchestrator,
          toolChoice: 'auto',
          messages,
          config: {
            temperature: 0.2, // Slightly more creative for better synthesis
            maxOutputTokens: config.ai.maxOutputTokens,
          }
        });
        
        let finalResponse: UniversalChatOutput;
        const toolRequest = response.toolRequests[0];

        if (toolRequest) {
            const toolName = toolRequest.name;
            const toolResponseData = toolRequest.input;

            logger.info(`[UniversalChat:Flow] AI requested tool: "${toolName}"`);

            const { output: finalOutput } = await finalResponsePrompt(
                { userQuery, toolResult: toolResponseData },
                { model: config.ai.model, config: { maxOutputTokens: config.ai.maxOutputTokens } }
            );
            
            if (!finalOutput) {
                throw new Error('The AI model did not return a valid final response object after tool use.');
            }

            finalResponse = {
                ...finalOutput,
                data: toolResponseData, // Attach the raw data for visualization
                toolName: toolName,
            };

        } else if(response.text) {
             logger.info(`[UniversalChat:Flow] AI generated a text-only response. Synthesizing final response.`);
            const { output: finalOutput } = await finalResponsePrompt(
                { userQuery, toolResult: response.text },
                { model: config.ai.model, config: { maxOutputTokens: config.ai.maxOutputTokens } }
            );

            if (!finalOutput) {
                throw new Error('The AI model did not return a valid final response object from text.');
            }

             finalResponse = {
                ...finalOutput,
                data: null,
                toolName: undefined,
            };

        } else {
             logger.warn("[UniversalChat:Flow] No tool or text was generated. Answering from general knowledge.");
             finalResponse = {
                response: "I'm sorry, I was unable to generate a specific response from your business data. Please try rephrasing your question.",
                data: [],
                visualization: { type: 'none', title: '', data: [] },
                confidence: 0.5,
                assumptions: ['I was unable to answer this from your business data and answered from general knowledge.'],
            };
        }
       
        if (isRedisEnabled) {
            await redisClient.set(cacheKey, JSON.stringify(finalResponse), 'EX', config.redis.ttl.aiQuery);
        }
        return finalResponse;

    } catch (e: unknown) {
        const errorMessage = getErrorMessage(e);
        logError(e, { context: `Universal Chat Flow failed for query: "${userQuery}"` });

        if (errorMessage.includes('503') || errorMessage.includes('unavailable') || errorMessage.includes('timed out')) {
             return {
                response: `I'm sorry, but the AI service is currently unavailable or took too long to respond. This may be a temporary issue. Please try again in a few moments.`,
                data: [],
                visualization: { type: 'none', title: '', data: [] },
                confidence: 0.0,
                assumptions: ['The AI service is unavailable.'],
                isError: true,
            };
        }

        return {
            response: `I'm sorry, but I encountered an unexpected error while trying to generate a response. The AI service may be temporarily unavailable. Please try again in a few moments.`,
            data: [],
            visualization: { type: 'none', title: '', data: [] },
            confidence: 0.0,
            assumptions: ['An unexpected error occurred in the AI processing flow.'],
            isError: true,
        };
    }
  }
);
