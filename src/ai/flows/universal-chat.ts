
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
import { getDemandForecast, getAbcAnalysis, getGrossMarginAnalysis, getNetMarginByChannel, getMarginTrends, getSalesVelocity, getPromotionalImpactAnalysis } from './analytics-tools';
import { logError, getErrorMessage } from '@/lib/error-handler';
import { isRedisEnabled, redisClient } from '@/lib/redis';
import crypto from 'crypto';
import { getProductDemandForecast } from './product-demand-forecast-flow';
import type { MessageData } from 'genkit';

const safeToolsForOrchestrator = [
    getEconomicIndicators,
    getDeadStockReport,
    getInventoryTurnoverReport,
    getDemandForecast,
    getAbcAnalysis,
    getGrossMarginAnalysis,
    getNetMarginByChannel,
    getMarginTrends,
    getSalesVelocity,
    getPromotionalImpactAnalysis,
    getProductDemandForecast,
];


const FinalResponseObjectSchema = UniversalChatOutputSchema.omit({ data: true, toolName: true });
const finalResponsePrompt = ai.definePrompt({
  name: 'finalResponsePrompt',
  input: { schema: z.object({ userQuery: z.string(), toolResult: z.string() }) },
  output: { schema: FinalResponseObjectSchema },
  prompt: `
    You are an expert AI inventory analyst for the ARVO application. Your tone is professional, intelligent, and helpful.
    The user asked: "{{userQuery}}"
    The result from your internal tools is:
    {{{toolResult}}}

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
        - Based on the data's structure, suggest an appropriate visualization. For now, since the direct data isn't passed, default to 'none'.
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
          messages,
          config: {
            maxOutputTokens: config.ai.maxOutputTokens,
          }
        });
        
        const text = response.text;

        if (text) {
            logger.info(`[UniversalChat:Flow] AI generated response. Synthesizing final response from text: "${text}"`);

            const { output: finalOutput } = await finalResponsePrompt(
                { userQuery, toolResult: text },
                {
                    model: config.ai.model,
                    config: { maxOutputTokens: config.ai.maxOutputTokens }
                }
            );

            if (!finalOutput) {
                throw new Error('The AI model did not return a valid final response object after tool use.');
            }

            const responseToCache: UniversalChatOutput = {
                ...finalOutput,
                data: null, // Data for visualization is not directly available in this simplified flow
                toolName: undefined,
            };

            if (isRedisEnabled) {
                await redisClient.set(cacheKey, JSON.stringify(responseToCache), 'EX', config.redis.ttl.aiQuery);
            }
            return responseToCache;

        }

        logger.warn("[UniversalChat:Flow] No text was generated. Answering from general knowledge.");

        const responseToCache: UniversalChatOutput = {
            response: "I'm sorry, I was unable to generate a specific response from your business data. Please try rephrasing your question.",
            data: [],
            visualization: { type: 'none', title: '' },
            confidence: 0.5,
            assumptions: ['I was unable to answer this from your business data and answered from general knowledge.'],
        };

        if (isRedisEnabled) {
            await redisClient.set(cacheKey, JSON.stringify(responseToCache), 'EX', config.redis.ttl.aiQuery);
        }
        return responseToCache;

    } catch (e: unknown) {
        const errorMessage = getErrorMessage(e);
        logError(e, { context: `Universal Chat Flow failed for query: "${userQuery}"` });

        if (errorMessage.includes('503') || errorMessage.includes('unavailable') || errorMessage.includes('timed out')) {
             return {
                response: `I'm sorry, but the AI service is currently unavailable or took too long to respond. This may be a temporary issue. Please try again in a few moments.`,
                data: [],
                visualization: { type: 'none', title: '' },
                confidence: 0.0,
                assumptions: ['The AI service is unavailable.'],
                isError: true,
            };
        }

        return {
            response: `I'm sorry, but I encountered an unexpected error while trying to generate a response. The AI service may be temporarily unavailable. Please try again in a few moments.`,
            data: [],
            visualization: { type: 'none', title: '' },
            confidence: 0.0,
            assumptions: ['An unexpected error occurred in the AI processing flow.'],
            isError: true,
        };
    }
  }
);

export const universalChatFlow = universalChatOrchestrator;
