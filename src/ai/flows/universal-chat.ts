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
  const { companyId } = flow.context;
  if (!companyId) {
      // If the companyId is missing, something is fundamentally wrong. Abort immediately.
      throw new Error("Security Error: Could not determine company ID for the query. Aborting.");
  }
  
  // This logic rewrites the AI's generated query to ALWAYS include a `WHERE company_id = ...` clause.
  // This is the most important security feature. It makes it impossible for the AI to query
  // data from another company, even if it tried to craft a malicious query.
  let secureQuery = query;
  const whereRegex = /\sWHERE\s/i;
  const fromRegex = /\sFROM\s[\w."]+\b/i;
  const fromMatch = secureQuery.match(fromRegex);

  if (fromMatch) {
    const fromClause = fromMatch[0];
    const tableName = fromClause.split(/\s/)[2];
    const securityClause = ` ${tableName}.company_id = '${companyId}' `;

    if (whereRegex.test(secureQuery)) {
      // If a WHERE clause exists, append our condition with AND
      secureQuery = secureQuery.replace(whereRegex, ` WHERE ${securityClause} AND `);
    } else {
      // If no WHERE clause, find where to insert it (before GROUP BY, ORDER BY, LIMIT, etc.)
      const otherClauses = [/\sGROUP\sBY\s/i, /\sORDER\sBY\s/i, /\sLIMIT\s/i];
      let insertionPoint = -1;
      for (const clauseRegex of otherClauses) {
        const match = secureQuery.match(clauseRegex);
        if (match && (match.index < insertionPoint || insertionPoint === -1)) {
            insertionPoint = match.index;
        }
      }
      if (insertionPoint !== -1) {
          secureQuery = `${secureQuery.slice(0, insertionPoint)} WHERE ${securityClause} ${secureQuery.slice(insertionPoint)}`;
      } else {
          secureQuery += ` WHERE ${securityClause}`;
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
    // Return a specific error to the LLM. This is critical for self-correction.
    throw new Error(`Query failed with error: ${error.message}. The attempted query was: ${query}`);
  }

  // A query that returns no results is a valid state, not an error.
  // The AI prompt will be instructed on how to handle an empty array.
  // Return an empty array if data is null or empty.
  return data || [];
});


// This schema defines the expected input for the flow. It now expects the conversation
// history to be pre-formatted in the exact structure that Genkit requires.
const UniversalChatInputSchema = z.object({
  companyId: z.string(),
  conversationHistory: z.array(z.object({
    role: z.enum(['user', 'assistant']),
    content: z.array(z.object({
        text: z.string()
    })),
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
 * The main flow for handling universal chat requests. It no longer retries on failure.
 */
export const universalChatFlow = ai.defineFlow({
  name: 'universalChatFlow',
  inputSchema: UniversalChatInputSchema,
  outputSchema: UniversalChatOutputSchema,
}, async (input) => {
  // The input is validated by the Zod schema.
  // The conversationHistory is now guaranteed to be in the correct format.
  const { companyId, conversationHistory } = input;
  
  console.log('[UniversalChat] Starting flow. History length:', conversationHistory.length);

  const messages = conversationHistory
    .filter(msg => msg && (msg.role === 'user' || msg.role === 'assistant'))
    .map(msg => ({
      role: msg.role === 'assistant' ? 'model' : 'user', // Gemini uses 'model' instead of 'assistant'
      content: msg.content
    }));
  
  const { output } = await ai.generate({
    model: APP_CONFIG.ai.model,
    tools: [executeSQLTool],
    history: messages,
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
    context: { companyId }, // Pass companyId securely to the tool's flow context
  });
  
  console.log('[UniversalChat] AI generation successful.');

  if (!output) {
    throw new Error("The model did not return a valid response.");
  }
  
  output.data = output.data ?? []; // Ensure data is always an array
  
  return output;
});
