
'use server';
/**
 * @fileoverview Implements the advanced, multi-agent AI chat system for AIventory.
 * This system uses a Chain-of-Thought approach with distinct steps for planning,
 * generation, validation, and response formulation to provide more accurate and
 * context-aware answers.
 */

import { ai } from '@/ai/genkit';
import * as redis from '@/lib/redis';
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
import { getEnhancedDemandForecast, getCompanyForecastSummary, getBulkEnhancedForecast } from './enhanced-forecasting-tools';
import { getDemandForecast, getAbcAnalysis, getGrossMarginAnalysis, getNetMarginByChannel, getMarginTrends, getSalesVelocity, getPromotionalImpactAnalysis } from './analytics-tools';
import { logError, getErrorMessage } from '@/lib/error-handler';
import crypto from 'crypto';
import type { GenerateOptions, GenerateResponse, MessageData, ToolArgument } from 'genkit';

// These are the tools that are safe and fully implemented for the AI to use.
const safeToolsForOrchestrator: ToolArgument[] = [
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
    getEnhancedDemandForecast,
    getCompanyForecastSummary,
    getBulkEnhancedForecast,
    getDemandForecast,
    getAbcAnalysis,
    getGrossMarginAnalysis,
    getNetMarginByChannel,
    getMarginTrends,
    getSalesVelocity,
    getPromotionalImpactAnalysis,
];


const FinalResponseObjectSchema = UniversalChatOutputSchema.omit({ data: true, toolName: true });

let _finalResponsePrompt: any;
const getFinalResponsePrompt = () => {
    if(!_finalResponsePrompt) {
        _finalResponsePrompt = ai.definePrompt({
            name: 'finalResponsePrompt',
            input: { schema: z.object({ userQuery: z.string(), toolResult: z.any() }) },
            output: { schema: FinalResponseObjectSchema },
            prompt: `
                You are an expert AI inventory analyst for the AIventory application. Your tone is professional, intelligent, and helpful.
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
    }
    return _finalResponsePrompt;
};


/**
 * A wrapper for the genkit.ai.generate call that includes retry logic with exponential backoff.
 * @param request The generation request object.
 * @returns A promise that resolves to the GenerateResponse.
 * @throws An error if the request fails after all retry attempts.
 */
async function generateWithRetry(request: GenerateOptions): Promise<GenerateResponse> {
    const MAX_RETRIES = 5; // Increased from 3 to 5
    let lastError: Error | undefined;

    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
        try {
            // Enhanced model selection strategy for better reliability
            let modelToUse = config.ai.model;
            if (attempt === 2) modelToUse = 'googleai/gemini-1.5-flash'; // Fast model as backup
            if (attempt === 3) modelToUse = 'googleai/gemini-1.5-pro-001'; // Alternative pro version
            if (attempt === 4) modelToUse = 'googleai/gemini-1.5-flash-001'; // Alternative flash version
            if (attempt === 5) modelToUse = 'googleai/gemini-1.5-flash-8b'; // Lightweight final fallback
            
            const finalRequest: GenerateOptions = { 
                ...request, 
                model: modelToUse as any,
                config: {
                    ...request.config,
                    temperature: Math.max(0.1, (request.config?.temperature || 0.2) - (attempt * 0.02)), // Reduce randomness with retries
                    maxOutputTokens: Math.min(request.config?.maxOutputTokens || 2048, 2048), // Ensure token limit
                    stopSequences: request.config?.stopSequences || ['<|endoftext|>', '\n\nHuman:', '\n\nUser:'],
                    candidateCount: 1, // Force single response for consistency
                }
            };
            
            logger.info(`[AI Generate] Attempt ${attempt}/${MAX_RETRIES} with model: ${modelToUse}`);
            const response = await ai.generate(finalRequest);
            
            // Validate response quality
            if (!response || (!response.text && !response.toolRequests)) {
                throw new Error('Empty response from AI model');
            }
            
            logger.info(`[AI Generate] Success on attempt ${attempt}`);
            return response;
            
        } catch (e: unknown) {
            lastError = e instanceof Error ? e : new Error(getErrorMessage(e));
            logger.warn(`[AI Generate] Attempt ${attempt}/${MAX_RETRIES} failed: ${lastError.message}`);
            
            if (attempt === MAX_RETRIES) break;

            // Enhanced exponential backoff with jitter
            const baseDelay = Math.pow(2, attempt - 1) * 1000; // 1s, 2s, 4s, 8s, 16s
            const jitter = Math.random() * 1000; // Add up to 1s random delay
            const delayMs = baseDelay + jitter;
            
            logger.info(`[AI Generate] Waiting ${Math.round(delayMs)}ms before retry ${attempt + 1}`);
            await new Promise(resolve => setTimeout(resolve, delayMs));
        }
    }
    
    logError(lastError, { context: 'AI generation failed after all retries.' });
    throw lastError;
}


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

    // Mock response for testing to avoid API quota issues
    if (process.env.MOCK_AI === 'true') {
      return {
        response: `I understand you're asking about "${userQuery}". Based on your inventory data, I can provide helpful insights about your business performance, product analysis, and recommendations. This is a mock response for testing purposes.`,
        visualization: {
          type: 'none' as const,
          title: 'Mock Analysis'
        },
        confidence: 0.9,
        assumptions: ['This is a mocked response for testing'],
        data: { mockData: true },
        toolName: 'mockTool'
      };
    }

    // --- Redis Caching Logic ---
    const queryHash = crypto.createHash('sha256').update(userQuery.toLowerCase().trim()).digest('hex');
    const cacheKey = `aichat:${companyId}:${queryHash}`;
    if (redis.isRedisEnabled) {
      try {
        const cachedResponse = await redis.redisClient.get(cacheKey);
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
        const genkitHistory: MessageData[] = conversationHistory.map(msg => ({
            role: msg.role as 'user' | 'model',
            content: msg.content,
        }));
        
        const response = await generateWithRetry({
            model: config.ai.model as any,
            system: `You are AIventory's expert inventory analyst AI. You help users understand their business data, make decisions, and optimize their inventory operations.

QUALITY STANDARDS:
- Always provide actionable insights, not just raw data
- Use business language, not technical jargon
- Be specific and confident in your recommendations
- If data is missing, suggest concrete next steps
- Focus on ROI and business impact

RESPONSE GUIDELINES:
- Keep responses concise but comprehensive (200-400 words ideal)
- Structure responses with clear sections when appropriate
- Always include confidence levels and assumptions
- Suggest appropriate visualizations for the data

AVAILABLE TOOLS: You have access to comprehensive inventory analytics tools including reorder suggestions, dead stock analysis, sales velocity, margin analysis, demand forecasting, and supplier performance data.`,
            tools: safeToolsForOrchestrator,
            messages: genkitHistory,
            config: {
                temperature: 0.15, // Lower temperature for more consistent responses
                maxOutputTokens: config.ai.maxOutputTokens,
                topP: 0.8, // Restrict token diversity for better quality
                topK: 40,  // Further restrict for consistency
            }
        });
        
        let finalResponse: UniversalChatOutput;
        const toolRequestPart = response.toolRequests?.[0];

        if (toolRequestPart) {
            const toolName = toolRequestPart.toolRequest?.name || 'unknown_tool';
            const toolResponseData = toolRequestPart.toolRequest?.input || {};

            logger.info(`[UniversalChat:Flow] AI requested tool: "${toolName}"`);

            const { output: finalOutput } = await getFinalResponsePrompt()(
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
            const { output: finalOutput } = await getFinalResponsePrompt()(
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
                data: null,
                visualization: { type: 'none', title: '', data: [] },
                confidence: 0.5,
                assumptions: ['I was unable to answer this from your business data and answered from general knowledge.'],
            };
        }
        
        if (finalResponse.confidence && finalResponse.confidence < 0.6) {
            finalResponse.response = `I'm not very confident in this result, but here is what I found:\n\n${finalResponse.response}\n\nMy assumptions were: ${finalResponse.assumptions?.join(', ') || 'none'}. You may want to try rephrasing your question for a more accurate answer.`;
        }
       
        if (redis.isRedisEnabled) {
            await redis.redisClient.set(cacheKey, JSON.stringify(finalResponse), 'EX', 3600);
        }
        return finalResponse;

    } catch (e: unknown) {
        const errorMessage = getErrorMessage(e) ?? '';
        logError(e, { context: `Universal Chat Flow failed for query: "${userQuery}"` });

        // Enhanced error categorization and user-friendly responses
        if (errorMessage.includes('quota') || errorMessage.includes('limit')) {
            return {
                response: `I'm currently experiencing high demand and have temporarily reached my processing limits. This is usually resolved within a few minutes. Please try again shortly, or contact support if this issue persists.`,
                data: null,
                visualization: { type: 'alert', title: 'Service Temporarily Unavailable', data: [] },
                confidence: 0.0,
                assumptions: ['API quota/rate limit exceeded'],
                is_error: true,
            };
        }

        if (errorMessage.includes('503') || errorMessage.includes('unavailable') || errorMessage.includes('timed out')) {
             return {
                response: `I'm sorry, but my AI service is currently experiencing technical difficulties. This is typically a temporary issue that resolves within a few minutes. Please try your question again in a moment.`,
                data: null,
                visualization: { type: 'alert', title: 'AI Service Unavailable', data: [] },
                confidence: 0.0,
                assumptions: ['AI service is temporarily unavailable'],
                is_error: true,
            };
        }
        
        if (errorMessage.includes('Invalid') || errorMessage.includes('parse') || errorMessage.includes('schema')) {
            return {
                response: `I encountered an issue understanding your request. This might be due to the way the question was phrased. Could you try rephrasing your question more simply? For example: "What should I reorder?" or "Show me my best selling products."`,
                data: null,
                visualization: { type: 'none', title: '', data: [] },
                confidence: 0.0,
                assumptions: ['Request parsing or validation error'],
                is_error: true,
            };
        }

        // Generic error response with helpful guidance
        return {
            response: `I encountered an unexpected error while processing your request about "${userQuery}". Here are some things you can try:

• **Simplify your question:** Try asking about one specific topic at a time
• **Use common terms:** Ask about "inventory," "sales," "profits," or "suppliers"  
• **Try again:** This might be a temporary issue that resolves quickly
• **Contact support:** If problems persist, our team can help troubleshoot

I'm designed to help with inventory management, sales analysis, and business insights. Feel free to try a different question!`,
            data: null,
            visualization: { type: 'alert', title: 'Processing Error', data: [] },
            confidence: 0.0,
            assumptions: ['Unexpected error in AI processing pipeline'],
            is_error: true,
        };
    }
  }
);
