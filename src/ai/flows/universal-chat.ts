'use server';

/**
 * @fileOverview Universal Chat flow with RAG capabilities using a dynamic SQL tool.
 * This file contains the core logic for how the AI interacts with the database.
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
 * The main flow for handling universal chat requests.
 * This has been re-architected to be more robust. The SQL tool is now
 * dynamically created within the flow's execution context, which securely
 * captures the companyId for each request, avoiding the fragile 'state'
 * passing mechanism that was causing crashes.
 */
export const universalChatFlow = ai.defineFlow({
  name: 'universalChatFlow',
  inputSchema: UniversalChatInputSchema,
  outputSchema: UniversalChatOutputSchema,
}, async (input) => {
  const { companyId, conversationHistory = [] } = input;
  
  console.log(`[UniversalChat] Starting flow for company ${companyId}. History length:`, conversationHistory.length);

  // Define the SQL tool within the flow's scope to securely capture the companyId.
  const executeSQLTool = ai.defineTool({
    name: 'executeSQL',
    description: `Executes a read-only SQL SELECT query against the company's database and returns the result as a JSON array.
      Use this tool to answer any question about inventory, suppliers, sales, or business data by constructing a valid SQL query.
      The 'company_id' is handled automatically by the system. Do NOT include it in your generated query.`,
    inputSchema: z.object({
      query: z.string().describe("The SQL SELECT query to execute. It MUST start with 'SELECT'."),
    }),
    outputSchema: z.array(z.any()),
  }, async ({ query }) => { // The 'flow' parameter is removed as it was the source of the error.
    
    // SECURITY VALIDATION: Allow only SELECT queries.
    if (!query.trim().toLowerCase().startsWith('select')) {
        throw new Error('For security reasons, only SELECT queries are allowed.');
    }
    
    // SECURE COMPANY ID INJECTION: companyId is now from the parent scope, not a fragile state object.
    const fromMatch = query.match(/\sFROM\s+([`"'\w]+)/i);
    if (!fromMatch || !fromMatch[1]) {
        throw new Error("Query does not specify a valid 'FROM' clause and cannot be secured.");
    }
    const tableName = fromMatch[1].replace(/[`"']/g, '');
    const securityClause = `${tableName}.company_id = '${companyId}'`;

    let secureQuery = query;
    const whereRegex = /\sWHERE\s/i;

    if (whereRegex.test(secureQuery)) {
        secureQuery = secureQuery.replace(whereRegex, ` WHERE ${securityClause} AND `);
    } else {
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

    // PERFORMANCE & COST CONTROL: Add a LIMIT clause.
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
      throw new Error(`Query failed with error: ${error.message}. The attempted query was: ${query}`);
    }

    return data || [];
  });
  
  // Filter and format messages for Gemini
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
      tools: [executeSQLTool], // Use the new, dynamically created tool
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
      // The `state` parameter is no longer needed because the companyId is baked into the tool's closure.
    });

    const output = modelResponse.output;
    
    if (!output) {
      console.error('[UniversalChat] AI model returned a null or invalid object.', modelResponse);
      throw new Error("The AI model did not return a valid response object. The output was null.");
    }
    
    output.data = output.data ?? [];
    
    return output;

  } catch (error) {
    console.error('[UniversalChat] An error occurred during AI generation:', error);
    throw error;
  }
});