
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
import { logError, getErrorMessage } from '@/lib/error-handler';

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
    You are ARVO, an expert AI inventory analyst. Your tone is professional, intelligent, and helpful.
    The user asked: "{{userQuery}}"
    You have executed a tool and received this JSON data as a result:
    {{{json toolResult}}}

    **YOUR TASK:**
    Your goal is to synthesize this raw data into a clear, concise, and actionable response for the user. Do NOT just repeat the data. Provide insight.

    **RESPONSE GUIDELINES:**

    1.  **Analyze & Synthesize**:
        - **If data exists:** Briefly summarize the key finding. Don't just list the data. For example, instead of saying "The data shows Vendor A has a 98% on-time rate", say "Vendor A is your most reliable supplier with a 98% on-time delivery rate."
        - **If data is empty or null:** Do not just say "No data found." Instead, provide a helpful and context-aware response. For example, if asked for dead stock and none is found, say "Good news! I didn't find any dead stock based on your current settings. Everything seems to be selling well."
        - **Special Case (Action Confirmation):** If the tool result contains a "createdPoCount" key, this was a user-confirmed action. Your primary response should be a clear success message, like "Done! I've created {{toolResult.createdPoCount}} new purchase orders. You can review them on the Purchase Orders page." Set the visualization type to 'none' for this case.

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
        
        try {
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
                data: toolResult.output,
                toolName: toolCall.name,
            };
        } catch (e) {
            logError(e, { context: `Tool execution failed for '${toolCall.name}'` });
            return {
                response: `I tried to use a tool to answer your question, but it failed with the following error: ${getErrorMessage(e)}`,
                data: [],
                visualization: { type: 'none', title: '' },
                confidence: 0.1,
                assumptions: ['The tool needed to answer your question failed to execute.'],
            }
        }
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
        visualization: { type: 'none', title: '' },
        confidence: 0.5,
        assumptions: ['I was unable to answer this from your business data and answered from general knowledge.'],
    };
  }
);

export const universalChatFlow = universalChatOrchestrator;
