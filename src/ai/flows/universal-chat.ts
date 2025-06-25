'use server';

/**
 * @fileOverview Universal Chat flow with RAG capabilities using a dynamic SQL tool.
 * This flow allows the AI to generate and execute SQL queries to answer a wide
 * range of questions about inventory, sales, and suppliers.
 */

import { ai } from '@/ai/genkit';
import { z } from 'genkit';
import { supabaseAdmin } from '@/lib/supabase/admin';

/**
 * Defines a Genkit Tool that allows the AI to execute SQL SELECT queries.
 * This is the core of the RAG implementation for the database.
 * The tool securely injects the company_id to prevent data leakage.
 */
const executeSQLTool = ai.defineTool({
  name: 'executeSQL',
  description: `Executes a read-only SQL SELECT query against the company's database and returns the result as a JSON array.
    Use this tool to answer any question about inventory, suppliers, sales, or business data by constructing a valid SQL query.`,
  inputSchema: z.object({
    query: z.string().describe("The SQL SELECT query to execute. It MUST start with 'SELECT'."),
  }),
  outputSchema: z.array(z.any()),
}, async ({ query }, flow) => {
  // Security check on the server side.
  if (!query.trim().toLowerCase().startsWith('select')) {
      throw new Error('For security reasons, only SELECT queries are allowed.');
  }

  // Get the companyId from the flow's state. This is more secure than passing it in the tool input.
  const { companyId } = flow.state;
  if (!companyId) {
      throw new Error("Could not determine company ID for the query.");
  }
  
  // Securely inject the company_id filter into the query.
  // This prevents the AI from forgetting or manipulating the WHERE clause.
  let secureQuery = query;
  const fromRegex = /\bFROM\b\s+([\w."]+)/i;
  const match = query.match(fromRegex);

  if (match) {
    const tableName = match[1];
    const whereClause = `WHERE ${tableName}.company_id = '${companyId}'`;

    if (query.toLowerCase().includes(' where ')) {
      secureQuery = query.replace(/ where /i, ` ${whereClause} AND `);
    } else {
      const groupByIndex = query.toLowerCase().indexOf(' group by ');
      if (groupByIndex > -1) {
        secureQuery = `${query.slice(0, groupByIndex)} ${whereClause} ${query.slice(groupByIndex)}`;
      } else {
        secureQuery = `${query} ${whereClause}`;
      }
    }
  } else {
    // Fallback for simple queries, though less common.
    if (!query.toLowerCase().includes('company_id')) {
        throw new Error("Query does not specify a table with 'FROM' and cannot be secured.");
    }
  }


  console.log('[SQL Tool] Executing Secure Query:', secureQuery);

  const { data, error } = await supabaseAdmin.rpc('execute_dynamic_query', {
      query_text: secureQuery
  });

  if (error) {
    console.error('SQL execution error:', error);
    // Provide a more user-friendly error message to the LLM.
    return [{ error: `Query failed: ${error.message}` }];
  }
  return data || [];
});


const UniversalChatInputSchema = z.object({
  message: z.string(),
  companyId: z.string(),
  conversationHistory: z.array(z.object({
    role: z.enum(['user', 'assistant']),
    content: z.string()
  })).optional()
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
 * The main flow for handling universal chat requests.
 * It uses ai.generate() for a more direct and robust way of interacting with the model.
 */
export const universalChatFlow = ai.defineFlow({
  name: 'universalChatFlow',
  inputSchema: UniversalChatInputSchema,
  outputSchema: UniversalChatOutputSchema,
}, async (input) => {
  const { message, companyId, conversationHistory = [] } = input;
  
  console.log('[UniversalChat] Starting flow with input:', input);

  try {
    const history = conversationHistory.map(msg => ({
      role: msg.role,
      content: [{text: msg.content}]
    }));

    const { output } = await ai.generate({
      model: 'gemini-2.0-flash',
      tools: [executeSQLTool],
      history: history,
      prompt: `You are InvoChat, a world-class conversational AI for inventory management. Your personality is helpful, proactive, and knowledgeable. You are an analyst that provides insights, not a simple database interface.

      **Database Schema You Can Query:**
      - inventory: id, company_id, sku, name, description, category, quantity, cost, price, reorder_point, reorder_qty, supplier_name, warehouse_name, last_sold_date
      - vendors: id, company_id, vendor_name, contact_info, address, terms, account_number
      - sales: id, company_id, sale_date, customer_name, total_amount, items
      - purchase_orders: id, company_id, po_number, vendor, item, quantity, cost, order_date

      **Business Logic & Concepts:**
      - Dead Stock: Items not sold in over 90 days (use 'last_sold_date').
      - Low Stock: Items where 'quantity' is less than or equal to 'reorder_point'.
      - Profit Margin: Calculate as '((price - cost) / price)'.
      - Inventory Turnover: A measure of how many times inventory is sold over a period. Can be complex, but you can query for Cost of Goods Sold (COGS) and average inventory value.

      **Your Goal:** Help the user understand their inventory data and make better decisions.

      **Core Instructions:**
      1.  **Analyze and Query:** Understand the user's message. If it requires data, formulate and execute the appropriate SQL query using the \`executeSQL\` tool. You can use JOINs, CTEs, and window functions.
      2.  **NEVER Show Your Work:** Do not show the raw SQL query to the user or mention that you are running one. Get the data and use it to answer the question conversationally.
      3.  **Provide Insights First:** Don't just dump data. Summarize your findings. For example, instead of just showing a table of 12 dead stock items, say "I found 12 items that haven't sold in over 90 days, with a total value of $X. The biggest concern is item Y."
      4.  **Offer Details & Visualizations:** After summarizing, offer to show the full data and suggest a relevant visualization type ('table', 'bar', 'pie', 'line').
      5.  **Be Proactive:** Suggest logical next steps. If items are low, suggest reordering. If stock is dead, suggest a sale.
      
      **Current User Message:** "${message}"

      Based on the user's message and the conversation history, decide if you need data. If so, use the \`executeSQL\` tool. Then, formulate your response and suggest a visualization if appropriate, all within a single JSON output.`,
      output: {
        schema: UniversalChatOutputSchema
      },
      // Pass companyId to the flow's state, accessible by tools.
      state: { companyId },
    });
    
    console.log('[UniversalChat] AI output:', output);

    if (!output) {
      throw new Error("The model did not return a valid response.");
    }
    
    // Ensure data is always an array to prevent client-side errors.
    if (output.data === null || output.data === undefined) {
      output.data = [];
    }
    
    return output;
    
  } catch (error: any) {
    console.error('[UniversalChat] Error in flow:', error);
    console.error('[UniversalChat] Error stack:', error.stack);
    
    // Provide a generic but helpful error message back to the user.
    return {
        response: "I'm sorry, but I encountered an issue while processing your request. It might be a temporary problem with the AI service. Please try again in a moment.",
        data: [],
        visualization: { type: 'none' }
    };
  }
});
