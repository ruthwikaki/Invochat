'use server';

/**
 * @fileOverview Universal Chat flow with RAG capabilities using a dynamic SQL tool.
 * This flow is designed for production use with enhanced security, error handling, and observability.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { supabaseAdmin } from '@/lib/supabase/admin';

/**
 * Defines a Genkit Tool that allows the AI to execute SQL SELECT queries.
 * This is the core of the RAG implementation for the database.
 * The tool securely injects the company_id to prevent data leakage and handles query validation.
 */
const executeSQLTool = ai.defineTool({
  name: 'executeSQL',
  description: `Executes a read-only SQL SELECT query against the company's database and returns the result as a JSON array.
    Use this tool to answer any question about inventory, suppliers, sales, or business data by constructing a valid SQL query.
    The 'company_id' is handled automatically by the system. Do NOT include it in your generated query.`,
  inputSchema: z.object({
    query: z.string().describe("The SQL SELECT query to execute. It MUST start with 'SELECT'."),
  }),
  outputSchema: z.array(z.any()),
}, async ({ query }, flow) => {
  // 1. Security Validation
  if (!query.trim().toLowerCase().startsWith('select')) {
      throw new Error('For security reasons, only SELECT queries are allowed.');
  }

  // 2. Secure companyId Injection
  const { companyId } = flow.state;
  if (!companyId) {
      throw new Error("Security Error: Could not determine company ID for the query. Aborting.");
  }
  
  // This is a more robust, though not infallible, way to inject the company_id.
  // A full SQL AST parser would be required for 100% correctness on all possible queries.
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
        const orderByIndex = query.toLowerCase().indexOf(' order by ');
        if (orderByIndex > -1) {
            secureQuery = `${query.slice(0, orderByIndex)} ${whereClause} ${query.slice(orderByIndex)}`;
        } else {
            secureQuery = `${query} ${whereClause}`;
        }
      }
    }
  } else {
    throw new Error("Query does not specify a table with 'FROM' and cannot be secured.");
  }

  // Add a LIMIT clause for performance and cost control
  if (!/limit\s+\d+/i.test(secureQuery)) {
    secureQuery += ' LIMIT 1000';
  }


  console.log('[executeSQLTool] Original query:', query);
  console.log('[executeSQLTool] Secure query:', secureQuery);
  console.log('[executeSQLTool] Company ID:', companyId);

  // 3. Database Execution
  const { data, error } = await supabaseAdmin.rpc('execute_dynamic_query', {
      query_text: secureQuery
  });

  console.log('[executeSQLTool] Result:', { data, error });

  if (error) {
    console.error('[executeSQLTool] SQL execution error:', error);
    // Return a specific error to the LLM.
    throw new Error(`Query failed with error: ${error.message}. The attempted query was: ${query}`);
  }

  if (data?.length >= 1000) {
    console.warn(`[executeSQLTool] Query returned max results (1000). Results may be truncated.`);
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
 * The main flow for handling universal chat requests with production-ready features like AI self-correction.
 */
export const universalChatFlow = ai.defineFlow({
  name: 'universalChatFlow',
  inputSchema: UniversalChatInputSchema,
  outputSchema: UniversalChatOutputSchema,
}, async (input) => {
  const { message, companyId, conversationHistory = [] } = input;
  
  console.log('[UniversalChat] Starting flow with input:', { message, companyId });

  const history = conversationHistory.map(msg => ({
    role: msg.role,
    content: [{text: msg.content}]
  }));

  const MAX_RETRIES = 2;
  for (let i = 0; i < MAX_RETRIES; i++) {
    try {
      const { output } = await ai.generate({
        model: 'googleai/gemini-1.5-pro',
        tools: [executeSQLTool],
        history: history,
        prompt: `You are InvoChat, a world-class conversational AI for inventory management. Your personality is helpful, proactive, and knowledgeable. You are an analyst that provides insights, not a simple database interface.

        **Database Schema You Can Query:**
        (Note: The 'company_id' is handled automatically by the tool. DO NOT include it in your queries.)
        - inventory: id, sku, name, description, category, quantity, cost, price, reorder_point, reorder_qty, supplier_name, warehouse_name, last_sold_date
        - vendors: id, vendor_name, contact_info, address, terms, account_number
        - sales: id, sale_date, customer_name, total_amount, items
        - purchase_orders: id, po_number, vendor, item, quantity, cost, order_date

        **Business Logic & Concepts:**
        - Dead Stock: Items not sold in over 90 days (use 'last_sold_date').
        - Low Stock: Items where 'quantity' is less than or equal to 'reorder_point'.
        - Profit Margin: Calculate as '((price - cost) / price)'.

        **Core Instructions:**
        1.  **Analyze and Query:** Understand the user's request. If it requires data, formulate and execute the appropriate SQL query using the \`executeSQL\` tool.
        2.  **Data First (when asked):** If the user explicitly asks for a list, a table, or "all" of something (e.g., "show me all products", "list my vendors"), your primary goal is to provide that data. In this case, use the tool and then set the \`visualization.type\` to 'table'. Your \`response\` text should be a brief introduction to the table.
        3.  **Insights First (for analysis):** If the user asks for an analysis, summary, or a "what is" question (e.g., "what's my best-selling item?", "summarize my sales"), provide a conversational insight first. Then, if relevant, you can include the data and suggest a visualization.
        4.  **Suggest Charts:** For analytical queries, if the data is suitable for a chart ('bar', 'pie', 'line'), suggest one. For example, data grouped by category is good for a pie or bar chart.
        5.  **NEVER Show Your Work:** Do not show the raw SQL query to the user or mention that you are running one.
        6.  **Error Handling:** If a tool call fails, the error will be provided. Analyze the error, fix the query, and retry. Only explain the error to the user if you cannot fix it.
        
        Base all responses strictly on data returned from the executeSQL tool. If a query returns empty results, acknowledge this directly.

        **Current User Message:** "${message}"

        Based on the user's message and the conversation history, decide if you need data. If so, use the \`executeSQL\` tool. Then, formulate your response and suggest a visualization if appropriate.`,
        output: {
          schema: UniversalChatOutputSchema
        },
        state: { companyId }, // Pass companyId securely to the tool's flow state
      });
      
      console.log('[UniversalChat] AI generation successful.');

      if (!output) {
        throw new Error("The model did not return a valid response.");
      }
      
      output.data = output.data ?? []; // Ensure data is always an array
      
      return output; // Success, exit loop
      
    } catch (error: any) {
      const errorMessage = `Attempt ${i + 1} failed: ${error.message}`;
      console.error(`[UniversalChat] ${errorMessage}`);

      if (i === MAX_RETRIES - 1) {
          console.error('[UniversalChat] Max retries reached. Returning error response.');
          // Re-throw the original error to be caught by the action handler
          throw error;
      }
      // Add error to history for the next attempt and instruct the AI to fix it.
      history.push({ role: 'user', content: [{ text: `The last tool call failed with this error: ${error.message}. Please analyze the error, fix the query based on the schema, and try again.` }] });
    }
  }

  // This part should be unreachable if MAX_RETRIES > 0
  throw new Error("Flow failed after all retries.");
});
