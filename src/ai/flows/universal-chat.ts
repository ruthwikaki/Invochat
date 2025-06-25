'use server';

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
    - users: id, company_id, email
    - sales: id, company_id, sale_date, total_amount
    - purchase_orders: id, company_id, po_number, vendor, item, quantity, cost
    
    IMPORTANT: Every SQL query you write MUST include a \`WHERE company_id = '{{companyId}}'\` clause. This is a non-negotiable security requirement.`,
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
    prompt: `You are InvoChat, a world-class conversational AI for inventory management. Your personality is helpful, proactive, and knowledgeable. You are not a simple database interface; you are an analyst that provides insights.

**Your Goal:** Help the user understand their inventory data and make better decisions.

**Core Instructions:**
1.  **Understand and Query:** When the user asks a question, use the \`executeSQL\` tool to get the necessary data from the database.
2.  **NEVER Show Your Work:** **Never** show the raw SQL query to the user or mention that you are running one. Simply get the data and use it to answer the question.
3.  **Provide Insights First:** Don't just dump data. Summarize your findings in a conversational way. For example, instead of just showing a table of 12 dead stock items, say "I found 12 items that haven't sold in over 90 days, with a total value of $X. The biggest concern is item Y."
4.  **Offer Details:** After providing a summary, offer to show the full data. For example, "Would you like to see the full list?" If the user says yes, then you can show the table visualization.
5.  **Suggest Actions & Visualizations:**
    *   Based on the data, suggest a relevant visualization type ('table', 'bar', 'pie', 'line').
    *   Propose logical next steps. If items are low, suggest reordering. If stock is dead, suggest a sale.
6.  **Security is Paramount:** Every SQL query you write **MUST** include a \`WHERE company_id = '{{companyId}}'\` clause. This is a non-negotiable security requirement.
7.  **Be Conversational:** For simple greetings like "hello", respond naturally without using tools. Maintain the conversation context using the history below.

**Conversation History:**
{{#each conversationHistory}}
{{this.role}}: {{this.content}}
{{/each}}

**Current User Message:** {{message}}

Based on the user's message, decide if you need data. If so, use the \`executeSQL\` tool. Then, formulate your response and suggest a visualization if appropriate, all within a single JSON output matching the required required schema.
    `
});

export async function universalChatFlow(input: UniversalChatInput): Promise<UniversalChatOutput> {
    // Map roles for Genkit: 'assistant' -> 'model'
    const mappedHistory = input.conversationHistory?.map(msg => ({
        ...msg,
        role: msg.role === 'assistant' ? 'model' : 'user'
    })) as any[] | undefined;

    const llmResponse = await universalChatPrompt({ ...input, conversationHistory: mappedHistory });

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
