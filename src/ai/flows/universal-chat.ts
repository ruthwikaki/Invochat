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
  if (!query.trim().toLowerCase().startsWith('select')) {
      throw new Error('For security reasons, only SELECT queries are allowed.');
  }

  // 2. SECURE COMPANY ID INJECTION: Enforce data isolation.
  // The user's companyId is retrieved from the secure flow state, not from AI input.
  const { companyId } = flow.state;
  if (!companyId) {
      throw new Error("Security Error: Could not determine company ID for the query. Aborting.");
  }
  
  // This logic rewrites the AI's generated query to ALWAYS include a `WHERE company_id = ...` clause.
  // This is the most important security feature. It makes it impossible for the AI to query
  // data from another company, even if it tried to craft a malicious query.
  const fromMatch = query.match(/\sFROM\s+([`"'\w]+)/i);
  if (!fromMatch || !fromMatch[1]) {
      throw new Error("Query does not specify a valid 'FROM' clause and cannot be secured.");
  }
  const tableName = fromMatch[1].replace(/[`"']/g, '');
  const securityClause = `${tableName}.company_id = '${companyId}'`;

  let secureQuery = query;
  const whereRegex = /\sWHERE\s/i;

  if (whereRegex.test(secureQuery)) {
      // If a WHERE clause exists, append our condition with AND
      secureQuery = secureQuery.replace(whereRegex, ` WHERE ${securityClause} AND `);
  } else {
      // If no WHERE clause, find where to insert it (before GROUP BY, ORDER BY, LIMIT, etc.)
      const otherClauses = [/\sGROUP\sBY\s/i, /\sORDER\sBY\s/i, /\sLIMIT\s/i, /;/i];
      let insertionPoint = -1;
      for (const clauseRegex of otherClauses) {
          const match = secureQuery.match(clauseRegex);
          if (match?.index !== undefined && (insertionPoint === -1 || match.index < insertionPoint)) {
              insertionPoint = match.index;
          }
      }
      if (insertionPoint !== -1) {
          secureQuery = `${secureQuery.slice(0, insertionPoint)} WHERE ${securityClause} ${secureQuery.slice(insertionPoint)}`;
      } else {
          secureQuery += ` WHERE ${securityClause}`;
      }
  }

  // 3. PERFORMANCE & COST CONTROL: Add a LIMIT clause.
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

  if (error) {
    console.error('[executeSQLTool] SQL execution error:', error);
    // Return a specific error to the LLM. This is critical for self-correction.
    throw new Error(`Query failed with error: ${error.message}. The attempted query was: ${query}`);
  }

  return data || [];
});


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
 * The main flow for handling universal chat requests.
 */
export const universalChatFlow = ai.defineFlow({
  name: 'universalChatFlow',
  inputSchema: UniversalChatInputSchema,
  outputSchema: UniversalChatOutputSchema,
}, async (input) => {
  const { companyId, conversationHistory = [] } = input;
  
  console.log('[UniversalChat] Starting flow. History length:', conversationHistory.length);

  // Filter and format messages for Gemini
  const filteredHistory = conversationHistory
    .filter(msg => msg && (msg.role === 'user' || msg.role === 'assistant') && typeof msg.content === 'string' && msg.content.length > 0);

  // Ensure the conversation starts with a user message (Gemini requirement)
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

  // If after filtering, no user message was ever found, the history is invalid for Gemini.
  // We start a new conversation with a default user message.
  if (messages.length === 0) {
    console.log('[UniversalChat] No valid user-initiated conversation history, using default "Hello" message.');
    messages.push({
      role: 'user',
      content: [{ text: conversationHistory.at(-1)?.content || 'Hello' }]
    });
  }
  
  try {
    const modelResponse = await ai.generate({
      model: APP_CONFIG.ai.model,
      tools: [executeSQLTool],
      messages: messages,
      system: `You are ARVO, an expert AI inventory management analyst. Your ONLY function is to answer user questions by querying a database using the \`executeSQL\` tool.

      **CRITICAL INSTRUCTIONS - YOU MUST FOLLOW THESE:**
      1.  **NEVER ASK FOR MORE INFORMATION.** Do not ask clarifying questions like "What information are you looking for?". You have all the context you need.
      2.  **IMMEDIATELY USE THE TOOL.** For any user question about inventory, products, vendors, or sales, your first and only action should be to construct and execute a SQL query using the \`executeSQL\` tool.
      3.  **HANDLE EMPTY RESULTS:** If the tool returns an empty result (\`[]\`), you MUST inform the user that no data was found for their request. DO NOT invent data and DO NOT say "Here is the data...".
      4.  **NEVER SHOW YOUR WORK:** Do not show the raw SQL query to the user or mention the database, SQL, or the tool.
      5.  Base all responses strictly on data returned from the \`executeSQL\` tool.

      **DATABASE SCHEMA:**
      (Note: The 'company_id' is handled automatically. DO NOT include it in your queries.)
      - **inventory**: Contains all product and stock item information. Use this table for questions about "products". Columns: \`id, sku, name, description, category, quantity, cost, price, reorder_point, reorder_qty, supplier_name, warehouse_name, last_sold_date\`.
      - **vendors**: Contains all supplier information. Use this table for questions about "suppliers" or "vendors". Columns: \`id, vendor_name, contact_info, address, terms, account_number\`.
      - **sales**: Records all sales transactions. Columns: \`id, sale_date, customer_name, total_amount, items\`.
      - **purchase_orders**: Tracks orders placed with vendors. Columns: \`id, po_number, vendor, item, quantity, cost, order_date\`.`,
      output: {
        schema: UniversalChatOutputSchema
      },
      state: { companyId }, // Use 'state' to pass secure data to tools.
    });

    const output = modelResponse.output;
    
    if (!output) {
      console.error('[UniversalChat] AI model returned a null or invalid object.', modelResponse);
      throw new Error("The AI model did not return a valid response object. The output was null.");
    }
    
    // Ensure data is always an array for easier client-side handling.
    output.data = output.data ?? [];
    
    return output;

  } catch (error) {
    console.error('[UniversalChat] An error occurred during AI generation:', error);
    // Re-throw the error to be handled by the calling action.
    throw error;
  }
});
