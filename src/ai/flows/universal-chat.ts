
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

// This schema accepts the raw history format from the client action.
const UniversalChatInputSchema = z.object({
  companyId: z.string(),
  conversationHistory: z.array(z.object({
    role: z.enum(['user', 'assistant', 'system']),
    content: z.string(),
  })),
});
export type UniversalChatInput = z.infer<typeof UniversalChatInputSchema>;


const UniversalChatOutputSchema = z.object({
  response: z.string().describe("The natural language response to the user."),
  data: z.array(z.any()).optional().nullable().describe("The raw data retrieved from the database, if any, for visualizations."),
  visualization: z.object({
    type: z.enum(['table', 'bar', 'pie', 'line', 'none']),
    title: z.string().optional(),
    config: z.any().optional()
  }).optional().describe("A suggested visualization for the data.")
});
export type UniversalChatOutput = z.infer<typeof UniversalChatOutputSchema>;


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

    // This RPC function must exist in the database.
    // We provide the SQL to create it in the setup-incomplete page.
    const { data, error } = await supabaseAdmin.rpc('execute_dynamic_query', {
        query_text: finalQuery
    });

    if (error) {
        console.error('[executeSQLTool] SQL execution error:', error);
        // Provide a clear error to the model so it can potentially correct the query.
        throw new Error(`Query failed with error: ${error.message}. The attempted query was: ${query}`);
    }

    return data || [];
});

/**
 * The main flow for handling universal chat requests.
 */
export const universalChatFlow = ai.defineFlow({
  name: 'universalChatFlow',
  inputSchema: UniversalChatInputSchema,
  outputSchema: UniversalChatOutputSchema,
}, async (input) => {
  const { companyId, conversationHistory = [] } = input;
  
  console.log(`[UniversalChat] Starting flow for company ${companyId}. History length:`, conversationHistory.length);

  // Filter and format messages for Gemini.
  // The API requires the conversation to start with a 'user' role.
  const filteredHistory = conversationHistory
    .filter(msg => msg && (msg.role === 'user' || msg.role === 'assistant') && typeof msg.content === 'string' && msg.content.length > 0);

  const messages: { role: 'user' | 'model'; content: { text: string; }[]; }[] = [];
  let foundFirstUser = false;
  
  for (const msg of filteredHistory) {
    if (!foundFirstUser && msg.role === 'user') {
      foundFirstUser = true;
    }
    if (foundFirstUser) {
        messages.push({
          role: msg.role === 'assistant' ? 'model' : 'user',
          content: [{ text: msg.content }]
        });
    }
  }

  // If after filtering, there are no valid messages, use the last user message.
  if (messages.length === 0) {
    const lastUserMessage = conversationHistory.filter(m => m.role === 'user').at(-1);
    console.log('[UniversalChat] No valid user-initiated conversation history, using last user message or default "Hello".');
    messages.push({
      role: 'user',
      content: [{ text: lastUserMessage?.content || 'Hello' }]
    });
  }
  
  try {
    const modelResponse = await ai.generate({
      model: APP_CONFIG.ai.model,
      tools: [executeSQLTool],
      messages: messages,
      system: `You are ARVO, an expert AI inventory management analyst. Your ONLY function is to answer user questions about business data by generating and executing SQL queries. You must base ALL responses strictly on data returned from the 'executeSQL' tool.

      **CRITICAL INSTRUCTIONS - YOU MUST FOLLOW THESE:**
      1.  **NEVER ASK FOR MORE INFORMATION.** Do not ask clarifying questions. You have all the context you need.
      2.  **IMMEDIATELY USE THE TOOL.** For any user question about inventory, products, vendors, or sales, your first and only action should be to construct and execute a SQL query using the \`executeSQL\` tool.
      3.  **NEVER SHOW YOUR WORK:** Do not show the raw SQL query to the user or mention the database, SQL, or the tool.
      4.  **NEVER INVENT DATA:** If the tool returns an empty result (\`[]\`), you MUST state that no data was found for their request. Do not apologize. Do not say "Here is the data...". If the tool returns an error, state that you were unable to retrieve the data.
      5.  **ANALYZE & VISUALIZE:** After receiving data, analyze it. If the data is a list of items, you MUST suggest a 'table' visualization. If it's suitable for a chart, you MUST suggest the appropriate chart type ('bar', 'pie', 'line'). If no data is returned, suggest 'none' for the visualization type.
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
