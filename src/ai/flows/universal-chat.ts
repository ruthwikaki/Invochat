
'use server';

/**
 * @fileOverview Universal Chat flow with RAG capabilities using a dynamic SQL tool.
 * This file contains the core logic for how the AI interacts with the database.
 * This version has been re-architected for stability and security.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { APP_CONFIG } from '@/config/app-config';
import {
  type UniversalChatInput,
  UniversalChatInputSchema,
  type UniversalChatOutput,
  UniversalChatOutputSchema,
} from '@/types/ai-schemas';

/**
 * Defines the SQL tool globally.
 * This tool is responsible for executing SQL queries against the database.
 * The `companyId` is passed securely via the flow's state.
 */
const executeSQLTool = ai.defineTool({
  name: 'executeSQL',
  description: `Executes a read-only SQL SELECT query against the company's database and returns the result as a JSON array.
    Use this tool to answer any question about inventory, suppliers, sales, or business data by constructing a valid SQL query.`,
  inputSchema: z.object({
    query: z.string().describe("The SQL SELECT query to execute. It MUST contain the `company_id = 'COMPANY_ID_PLACEHOLDER'` clause."),
  }),
  outputSchema: z.array(z.any()),
}, async ({ query }, flow) => {
    // This is the secure, correct way to get request-scoped data into a tool.
    // The `state` is passed from the `ai.generate()` call within the flow.
    const companyId = flow?.state?.companyId;
    if (!companyId) {
        throw new Error("[executeSQLTool] Critical security error: companyId was not found in the flow's execution state. Aborting query.");
    }
    
    // SECURITY VALIDATION: Allow only SELECT queries.
    if (!query.trim().toLowerCase().startsWith('select')) {
        throw new Error('For security reasons, only SELECT queries are allowed.');
    }

    // SECURITY VALIDATION: Ensure the placeholder is present. This is a critical safeguard.
    if (!query.includes('COMPANY_ID_PLACEHOLDER')) {
        throw new Error("Query is insecure. It is missing the required `company_id = 'COMPANY_ID_PLACEHOLDER'` clause. Please regenerate the query correctly.");
    }

    // SECURE COMPANY ID INJECTION: Replace the placeholder with the actual companyId.
    const secureQuery = query.replace(/COMPANY_ID_PLACEHOLDER/g, companyId);
    
    // PERFORMANCE & COST CONTROL: Add a LIMIT clause if one doesn't already exist.
    let finalQuery = secureQuery;
    if (!/limit\s+\d+/i.test(finalQuery)) {
        finalQuery = finalQuery.replace(/;?$/, ` LIMIT ${APP_CONFIG.database.queryLimit};`);
    }

    console.log('[executeSQLTool] Original query from AI:', query);
    console.log('[executeSQLTool] Secured & Executed query:', finalQuery);

    const QUERY_TIMEOUT_MS = 10000; // 10 seconds
    const queryPromise = supabaseAdmin.rpc('execute_dynamic_query', {
        query_text: finalQuery
    });
    
    const timeoutPromise = new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`Query timed out after ${QUERY_TIMEOUT_MS / 1000} seconds. The query may be too complex.`)), QUERY_TIMEOUT_MS)
    );

    const result = await Promise.race([queryPromise, timeoutPromise]) as { data: any, error: any };
    const { data, error } = result;

    if (error) {
        console.error('[executeSQLTool] SQL execution error:', error);
        // Provide a clear error to the model so it can potentially correct the query.
        throw new Error(`Query failed with error: ${error.message}. The attempted query was: ${query}`);
    }

    return data || [];
});

/**
 * The internal Genkit flow definition.
 * It is NOT exported directly to comply with 'use server' constraints.
 */
const _universalChatFlow = ai.defineFlow({
  name: 'universalChatFlow',
  inputSchema: UniversalChatInputSchema,
  outputSchema: UniversalChatOutputSchema,
}, async (input) => {
  const { companyId, conversationHistory } = input;
  console.log(`[UniversalChat] Starting flow for company ${companyId}. History length: ${conversationHistory.length}`);
  console.log('[UniversalChat] Google API Key exists:', !!process.env.GOOGLE_API_KEY);
  
  // The AI requires the history to be in a specific format.
  // It must alternate between 'user' and 'model' roles.
  let geminiHistory = conversationHistory
      .map((msg) => ({
          role: msg.role === 'assistant' ? ('model' as const) : ('user' as const),
          content: [{ text: msg.content }], // Wrap content in the required structure.
      }));

  // The Gemini API requires that the history starts with a 'user' message.
  // Find the first user message and slice the array from that point.
  const firstUserIndex = geminiHistory.findIndex(msg => msg.role === 'user');
  if (firstUserIndex > 0) {
      geminiHistory = geminiHistory.slice(firstUserIndex);
  } else if (firstUserIndex === -1) {
    // If no user message is found, which is unlikely but possible, 
    // we should not send any history to avoid API errors.
    geminiHistory = [];
  }
  
  try {
    console.log('[UniversalChat] Calling AI.generate...');
    console.log('[UniversalChat] Model:', APP_CONFIG.ai.model);
    console.log('[UniversalChat] Tools passed:', [executeSQLTool].map(t => t.name));
    console.log('[UniversalChat] Last user message:', conversationHistory[conversationHistory.length - 1]?.content);

    const modelResponse = await ai.generate({
      model: APP_CONFIG.ai.model,
      tools: [executeSQLTool],
      history: geminiHistory,
      prompt: `User asked: "${conversationHistory[conversationHistory.length - 1]?.content}". You MUST use the executeSQL tool to query the database and answer this question. Do not respond without using the tool first.`,
      system: `You are ARVO, an expert AI inventory management analyst. Your ONLY function is to answer user questions about business data by generating and executing SQL queries. You must base ALL responses strictly on data returned from the 'executeSQL' tool.

      **CRITICAL INSTRUCTIONS - YOU MUST FOLLOW THESE:**
      1.  **NEVER ASK FOR MORE INFORMATION.** Do not ask clarifying questions. You have all the context you need.
      2.  **IMMEDIATELY USE THE TOOL.** For any user question about inventory, products, vendors, or sales, your first and only action should be to construct and execute a SQL query using the \`executeSQL\` tool.
      3.  **NEVER SHOW YOUR WORK:** Do not show the raw SQL query to the user or mention the database, SQL, or the tool.
      4.  **NEVER INVENT DATA:** If the tool returns an empty result (\`[]\`), you MUST state that no data was found for their request. Do not apologize. If the tool returns an error, state that you were unable to retrieve the data.
      5.  **ANALYZE & VISUALIZE:** After receiving data, you MUST populate the 'visualization' object. If the data is a list of items (e.g., product names, supplier lists), set 'visualization.type' to 'table'. If the data represents quantities or values suitable for a chart (e.g., sales totals by category), set 'visualization.type' to the most appropriate chart type ('bar', 'pie', 'line'). If no data is returned or the query fails, you MUST set 'visualization.type' to 'none'. You MUST also provide a descriptive 'visualization.title' for any table or chart you suggest.
      6.  **MANDATORY DATA RETURN:** If the \`executeSQL\` tool returns data, you MUST populate the 'data' field in your output with the exact data returned by the tool. This is not optional.
      
      **CRITICAL QUERYING RULE:**
      For every table you query (e.g., 'inventory', 'vendors'), you MUST include a condition in the WHERE clause to filter by the company ID. Use the exact placeholder 'COMPANY_ID_PLACEHOLDER' for the ID. The system will securely replace this placeholder. Queries without this placeholder will be rejected.
      - Example (1 table): \`SELECT name, quantity FROM inventory WHERE quantity < 10 AND company_id = 'COMPANY_ID_PLACEHOLDER'\`
      - Example (JOIN): \`SELECT i.name, s.total_amount FROM inventory i JOIN sales s ON i.id = s.item_id WHERE i.company_id = 'COMPANY_ID_PLACEHOLDER' AND s.company_id = 'COMPANY_ID_PLACEHOLDER'\`

      **DATABASE SCHEMA:**
      - **inventory**: Contains all product and stock item information. Columns: \`id, sku, name, description, category, quantity, cost, price, reorder_point, reorder_qty, supplier_name, warehouse_name, last_sold_date\`.
      - **vendors**: Contains all supplier information. Columns: \`id, vendor_name, contact_info, address, terms, account_number\`.
      - **sales**: Records all sales transactions. Columns: \`id, sale_date, customer_name, total_amount, items\`.
      - **purchase_orders**: Tracks orders placed with vendors. Columns: \`id, po_number, vendor, item, quantity, cost, order_date\`.`,
      output: {
        schema: UniversalChatOutputSchema
      },
      // This is the correct way to pass request-scoped context to tools.
      state: input, 
    });

    console.log('[UniversalChat] Model response structure:', {
      hasOutput: !!modelResponse.output,
      outputKeys: modelResponse.output ? Object.keys(modelResponse.output) : [],
      hasToolCalls: !!modelResponse.toolCalls && modelResponse.toolCalls.length > 0,
      toolCalls: modelResponse.toolCalls,
    });
    console.log('[UniversalChat] AI output object:', JSON.stringify(modelResponse.output, null, 2));


    const output = modelResponse.output;
    
    if (!output) {
      console.error('[UniversalChat] AI model returned a null or invalid object.', modelResponse);
      throw new Error("The AI model did not return a valid response object. The output was null.");
    }
    
    // Ensure data is always an array, even if null/undefined from AI.
    output.data = output.data ?? [];
    
    return output;

  } catch (error) {
    console.error('[UniversalChat] An error occurred during AI generation:', error);
    // Rethrow the error to be handled by the calling server action.
    throw error;
  }
});


/**
 * This is the single, exported async function that wraps the Genkit flow.
 * It is the only function exported from this file to comply with 'use server' constraints.
 */
export async function universalChatFlow(input: UniversalChatInput): Promise<UniversalChatOutput> {
  return await _universalChatFlow(input);
}
