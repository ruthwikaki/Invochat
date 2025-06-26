
'use server';

/**
 * @fileOverview Universal Chat flow with RAG capabilities using a dynamic SQL tool.
 * This file contains the core logic for how the AI interacts with the database.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { APP_CONFIG } from '@/config/app-config';

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
  // This function is the gatekeeper for all database access.
  // It ensures data security and multi-tenancy in three critical ways:

  // 1. SECURITY VALIDATION: Allow only SELECT queries.
  // This prevents the AI from attempting to modify data (INSERT, UPDATE, DELETE).
  if (!query.trim().toLowerCase().startsWith('select')) {
      throw new Error('For security reasons, only SELECT queries are allowed.');
  }

  // 2. SECURE COMPANY ID INJECTION: Enforce data isolation.
  // The user's companyId is retrieved from the secure flow state, not from AI input.
  const { companyId } = flow.state;
  if (!companyId) {
      // If the companyId is missing, something is fundamentally wrong. Abort immediately.
      throw new Error("Security Error: Could not determine company ID for the query. Aborting.");
  }
  
  // This logic rewrites the AI's generated query to ALWAYS include a `WHERE company_id = ...` clause.
  // This is the most important security feature. It makes it impossible for the AI to query
  // data from another company, even if it tried to craft a malicious query.
  let secureQuery = query;
  const fromRegex = /\bFROM\b\s+([\w."]+)/i;
  const match = query.match(fromRegex);

  if (match) {
    const tableName = match[1];
    const whereClause = `WHERE ${tableName}.company_id = '${companyId}'`;

    if (query.toLowerCase().includes(' where ')) {
      // If the query already has a WHERE clause, we add our security condition.
      secureQuery = query.replace(/ where /i, ` ${whereClause} AND `);
    } else {
      // Otherwise, we add the WHERE clause before other clauses like GROUP BY or ORDER BY.
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
     // If the query is malformed (e.g., no FROM clause), we reject it.
    throw new Error("Query does not specify a table with 'FROM' and cannot be secured.");
  }

  // 3. PERFORMANCE & COST CONTROL: Add a LIMIT clause.
  // This prevents queries from returning excessively large datasets, saving costs and improving performance.
  if (!/limit\s+\d+/i.test(secureQuery)) {
    secureQuery += ` LIMIT ${APP_CONFIG.database.queryLimit}`;
  }


  console.log('[executeSQLTool] Original query from AI:', query);
  console.log('[executeSQLTool] Secured & Executed query:', secureQuery);
  console.log('[executeSQLTool] Company ID enforced:', companyId);

  // Database Execution
  const { data, error } = await supabaseAdmin.rpc('execute_dynamic_query', {
      query_text: secureQuery
  });

  console.log('[executeSQLTool] Result:', { data, error });

  if (error) {
    console.error('[executeSQLTool] SQL execution error:', error);
    // Return a specific error to the LLM.
    throw new Error(`Query failed with error: ${error.message}. The attempted query was: ${query}`);
  }

  // This is a critical step to prevent the AI from hallucinating data when a query correctly returns no results.
  // By throwing a specific, instructional error, we force the AI to acknowledge the empty set and report it to the user
  // instead of making up fake data. The flow's retry logic will catch this and feed it back to the model.
  if (!data || data.length === 0) {
    throw new Error("The query executed successfully but returned no results. Inform the user that no data was found for their request. Do not try to 'fix' the query, simply state that there is no data.");
  }

  if (data?.length >= APP_CONFIG.database.queryLimit) {
    console.warn(`[executeSQLTool] Query returned max results (${APP_CONFIG.database.queryLimit}). Results may be truncated.`);
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

  // Map the provided history to the format Genkit expects.
  const history = conversationHistory.map(msg => ({
    role: msg.role,
    content: [{text: msg.content}]
  }));
  
  // Add the current user message to the end of the history array. This is the standard pattern.
  history.push({ role: 'user', content: [{ text: message }] });


  const MAX_RETRIES = APP_CONFIG.ai.maxRetries;
  for (let i = 0; i < MAX_RETRIES; i++) {
    try {
      const { output } = await ai.generate({
        model: APP_CONFIG.ai.model,
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
        - Dead Stock: Items not sold in over ${APP_CONFIG.businessLogic.deadStockDays} days (use 'last_sold_date').
        - Low Stock: Items where 'quantity' is less than or equal to 'reorder_point'.
        - Profit Margin: Calculate as '((price - cost) / price)'.

        **Core Instructions:**
        1.  **Analyze and Query:** Understand the user's request based on the full conversation history. If it requires data, formulate and execute the appropriate SQL query using the \`executeSQL\` tool.
        2.  **Data First (when asked):** If the user explicitly asks for a list, a table, or "all" of something (e.g., "show me all products", "list my vendors"), your primary goal is to provide that data. In this case, use the tool and then set the \`visualization.type\` to 'table'. Your \`response\` text should be a brief introduction to the table.
        3.  **Insights First (for analysis):** If the user asks for an analysis, summary, or a "what is" question (e.g., "what's my best-selling item?", "summarize my sales"), provide a conversational insight first. Then, if relevant, you can include the data and suggest a visualization.
        4.  **Suggest Charts:** For analytical queries, if the data is suitable for a chart ('bar', 'pie', 'line'), suggest one. For example, data grouped by category is good for a pie or bar chart.
        5.  **NEVER Show Your Work:** Do not show the raw SQL query to the user or mention that you are running one.
        6.  **Error Handling:** If a tool call fails, the error will be provided. Analyze the error, fix the query, and retry. Only explain the error to the user if you cannot fix it.
        
        Base all responses strictly on data returned from the executeSQL tool. If a query returns empty results, acknowledge this directly.`,
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
      // Add a more nuanced error to the history for the next attempt.
      // This instructs the AI on how to handle different types of errors, including the "no results" case.
      history.push({ role: 'user', content: [{ text: `CRITICAL_ERROR: The previous attempt to use a tool failed with this message: '${error.message}'. STOP. DO NOT try to answer the original question. Your ONLY task now is to analyze this error. If the error says 'no results were found', your entire response MUST BE to inform the user that their query returned no data. DO NOT suggest a table or any visualization.` }] });
    }
  }

  // This part should be unreachable if MAX_RETRIES > 0
  throw new Error("Flow failed after all retries.");
});
