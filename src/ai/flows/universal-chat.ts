
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
import { getSupplierPerformanceReport } from './supplier-performance-tool';
import { createPurchaseOrdersTool } from './create-po-tool';
import { getDeadStockReport } from './dead-stock-tool';
import { getInventoryTurnoverReport } from './inventory-turnover-tool';
import { getDemandForecast, getAbcAnalysis, getGrossMarginAnalysis, getNetMarginByChannel, getMarginTrends } from './analytics-tools';
import { logError } from '@/lib/error-handler';

// List of all available tools for the AI to use.
const allTools = [
    getEconomicIndicators, 
    getReorderSuggestions, 
    getSupplierPerformanceReport, 
    createPurchaseOrdersTool, 
    getDeadStockReport, 
    getInventoryTurnoverReport,
    getDemandForecast,
    getAbcAnalysis,
    getGrossMarginAnalysis,
    getNetMarginByChannel,
    getMarginTrends
];

const FinalResponseObjectSchema = UniversalChatOutputSchema.omit({ data: true, toolName: true });
const finalResponsePrompt = ai.definePrompt({
  name: 'finalResponsePrompt',
  input: { schema: z.object({ userQuery: z.string(), toolResult: z.any() }) },
  output: { schema: FinalResponseObjectSchema },
  prompt: `
    You are InvoChat, an expert AI inventory analyst.
    The user asked: "{{userQuery}}"
    You have executed a tool and received this JSON data:
    {{{json toolResult}}}

    YOUR TASK:
    1.  **Analyze Data**:
        - Review the JSON data. If it's empty or null, state that you found no information.
        - **Special Case:** If the JSON data contains a "createdPoCount" key, your main task is to confirm the action. Your response should be a success message, for example: "Done! I've created 2 new purchase orders. You can view them on the Purchase Orders page." In this case, you should also suggest a 'none' visualization type.
        - Your analysis should be based *only* on the data provided.
    2.  **Formulate Response**:
        - Provide a concise, natural language response based on the database data.
        - Do NOT mention databases, JSON, or the specific tool you used.
    3.  **Assess Confidence**: Based on the user's query and the data, provide a confidence score from 0.0 to 1.0. A 1.0 means you are certain the query fully answered the user's request. A lower score means you had to make assumptions.
    4.  **List Assumptions**: If your confidence is below 1.0, list the assumptions you made (e.g., "Interpreted 'top products' as 'top by sales value'"). If confidence is 1.0, return an empty array.
    5.  **Suggest Visualization**: Based on the data's structure, suggest a visualization type and a title for it. Available types are: 'table', 'bar', 'pie', 'line', 'treemap', 'scatter', 'none'.
    6.  **Format Output**: Return a single JSON object with 'response', 'visualization', 'confidence', and 'assumptions' fields. Do NOT include the raw data in your response.
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
    
    const aiModel = config.ai.model;
    
    // Step 1: Let the AI decide if a tool is needed.
    const { toolCalls } = await ai.generate({
      model: aiModel,
      tools: allTools,
      history: conversationHistory.slice(0, -1),
      prompt: `The user's company ID is ${companyId}. Use this when calling any tool that requires a companyId. User's question: "${userQuery}"`,
    });
    
    // Step 2: If a tool is chosen, execute it.
    if (toolCalls && toolCalls.length > 0) {
        const toolCall = toolCalls[0];
        logger.info(`[UniversalChat:Flow] AI chose to use a tool: ${toolCall.name}`);
        
        const toolResult = await ai.runTool(toolCall);
        
        // Step 3: Use a second AI call to formulate a natural language response from the tool's data.
        const { output: finalOutput } = await finalResponsePrompt(
            { userQuery, toolResult: toolResult.output },
            { model: aiModel }
        );

        if (!finalOutput) {
            throw new Error('The AI model did not return a valid final response object after tool use.');
        }
        
        return {
            ...finalOutput,
            data: toolResult.output as any[],
            toolName: toolCall.name,
        };
    }

    // Step 4: If no tool is called, the AI should answer directly.
    logger.warn("[UniversalChat:Flow] No tool was called. Answering from general knowledge.");
    const { text } = await ai.generate({
        model: aiModel,
        history: conversationHistory.slice(0, -1),
        prompt: userQuery,
    });

    return {
        response: text,
        data: [],
        visualization: { type: 'none' },
        confidence: 0.5,
        assumptions: ['I was unable to answer this from your business data and answered from general knowledge.'],
    };
  }
);

export const universalChatFlow = universalChatOrchestrator;
