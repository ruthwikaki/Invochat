'use server';

/**
 * @fileOverview Universal Chat flow with RAG capabilities using a dynamic SQL tool.
 */

import { ai } from '@/ai/genkit';
import { z } from 'genkit';
import { supabaseAdmin } from '@/lib/supabase/admin';

// This tool lets the AI execute ANY SQL query it needs
const executeSQLTool = ai.defineTool({
  name: 'executeSQL',
  description: `Executes a SQL SELECT query against the company's database and returns the result as a JSON array.
    Available tables and their columns:
    - inventory: id, company_id, sku, name, description, category, quantity, cost, price, reorder_point, reorder_qty, supplier_name, warehouse_name, last_sold_date
    - vendors: id, company_id, vendor_name, contact_info, address, terms, account_number
    - companies: id, name
    Use this tool to answer any question about inventory, suppliers, or business data by constructing a valid SQL SELECT query.`,
  inputSchema: z.object({
    query: z.string().describe("The SQL SELECT query to execute. It must start with 'SELECT'."),
  }),
  outputSchema: z.array(z.any()),
}, async ({ query }) => {
  // Security check on the server side as well.
  if (!query.trim().toLowerCase().startsWith('select')) {
      throw new Error('For security reasons, only SELECT queries are allowed.');
  }

  // The RPC function will handle JSON aggregation. RLS is bypassed by service_role key,
  // so the query MUST contain a "WHERE company_id = '...'" clause, which the prompt instructs the LLM to add.
  const { data, error } = await supabaseAdmin.rpc('execute_dynamic_query', {
      query_text: query
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
      role: z.enum(['user', 'model']), // Genkit uses 'model' for assistant
      content: z.string()
    })).optional()
});
export type UniversalChatInput = z.infer<typeof UniversalChatInputSchema>;


const UniversalChatOutputSchema = z.object({
    response: z.string().describe("The natural language response to the user."),
    data: z.array(z.any()).optional().nullable().describe("The raw data retrieved from the database, if any. To be used for visualizations."),
    suggestedVisualization: z.enum(['table', 'bar', 'pie', 'line', 'none']).optional().describe("The suggested visualization type based on the user's query and the data.")
});
export type UniversalChatOutput = z.infer<typeof UniversalChatOutputSchema>;


const universalChatPrompt = ai.definePrompt({
    name: 'universalChatPrompt',
    input: { schema: UniversalChatInputSchema },
    output: { schema: UniversalChatOutputSchema },
    tools: [executeSQLTool],
    prompt: `You are InvoChat, an expert inventory management assistant. Your goal is to provide accurate, data-driven answers to the user.

**CRITICAL INSTRUCTIONS:**
1.  When the user asks a question that requires data, you **MUST** use the \`executeSQL\` tool to query the database.
2.  **NEVER** show the raw SQL query to the user. Do not ask for permission to run it. Just use the tool to get the data and then answer the question.
3.  **SECURITY REQUIREMENT:** Every SQL query you write **MUST** include a \`WHERE company_id = '{{companyId}}'\` clause to ensure you only access data for the current user's company. This is a mandatory security filter.
4.  Analyze the tool's output to formulate a helpful, natural language response.
5.  Based on the query and the data, suggest a suitable visualization ('table', 'bar', 'pie', 'line', or 'none').
6.  If the tool returns an error, inform the user gracefully that you couldn't retrieve the data.
7.  For simple conversational messages (like "hello" or "thank you"), just respond naturally without using any tools.

Conversation history:
{{#each conversationHistory}}
{{this.role}}: {{this.content}}
{{/each}}

Current user message: {{message}}

Your final output must be a single JSON object matching the defined output schema.
    `
});

export async function universalChatFlow(input: UniversalChatInput): Promise<UniversalChatOutput> {
    const llmResponse = await universalChatPrompt(input);

    const output = llmResponse.output;
    if (!output) {
      throw new Error("The model did not return a valid response.");
    }
    
    // Ensure data is an array, even if the model returns null/undefined, to prevent client-side errors.
    if (output.data === null || output.data === undefined) {
        output.data = [];
    }

    return output;
}
