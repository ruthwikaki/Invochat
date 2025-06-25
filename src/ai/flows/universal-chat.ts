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
    
    IMPORTANT: Every SQL query you write MUST include a \`WHERE company_id = '...' \` clause. This is a non-negotiable security requirement.`,
  inputSchema: z.object({
    query: z.string().describe("The SQL SELECT query to execute. It must start with 'SELECT'."),
  }),
  outputSchema: z.array(z.any()),
}, async ({ query }) => {
  // Security check on the server side as well.
  if (!query.trim().toLowerCase().startsWith('select')) {
      throw new Error('For security reasons, only SELECT queries are allowed.');
  }

  console.log('Executing SQL:', query); // Debug log

  const { data, error } = await supabaseAdmin.rpc('execute_dynamic_query', {
      query_text: query
  });

  if (error) {
    console.error('SQL execution error:', error);
    return [{ error: `Query failed: ${error.message}` }];
  }
  
  console.log('Query result:', data); // Debug log
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
    data: z.array(z.any()).optional().nullable().describe("The raw data retrieved from the database, if any. To be used for visualizations."),
    visualization: z.object({
        type: z.enum(['table', 'bar', 'pie', 'line', 'none']),
        title: z.string().optional(),
        config: z.any().optional()
    }).optional()
});
export type UniversalChatOutput = z.infer<typeof UniversalChatOutputSchema>;


export const universalChatFlow = ai.defineFlow({
  name: 'universalChatFlow',
  inputSchema: UniversalChatInputSchema,
  outputSchema: UniversalChatOutputSchema,
}, async (input) => {
    console.log('[UniversalChat] Starting flow with input:', input);
    
    const { message, companyId, conversationHistory = [] } = input;

    // Verify we have required data
    if (!companyId) {
      throw new Error('Company ID is required but was not provided');
    }

    if (!ai) {
      throw new Error('AI instance is not initialized');
    }

    try {
      // Create the prompt with the tools
      const prompt = ai.definePrompt({
          name: 'universalChatPrompt',
          input: { 
              schema: z.object({
                  message: z.string(),
                  companyId: z.string(),
                  history: z.string()
              }) 
          },
          output: { schema: UniversalChatOutputSchema },
          tools: [executeSQLTool],
          prompt: `You are InvoChat, an intelligent inventory assistant. You help users understand their inventory data through natural conversation.

          Current conversation:
          {{{history}}}

          User's message: {{{message}}}
          Company ID: {{{companyId}}}

          Instructions:
          1. When users ask about inventory value, use the executeSQL tool to query: SELECT SUM(quantity * cost) as total_value FROM inventory WHERE company_id = '{{{companyId}}}'
          2. Security is paramount: Every SQL query you write **MUST** include a WHERE company_id = '{{{companyId}}}' clause.
          3. NEVER show SQL queries or technical details to the user.
          4. Provide insights and summaries, not just raw data.
          5. Be conversational and helpful.

          Remember: You're an intelligent assistant. When asked about inventory data, ACTUALLY query the database and return helpful insights.`
      });

      console.log('[UniversalChat] Prompt created successfully');

      // Format conversation history
      const historyText = conversationHistory
          .map(msg => `${msg.role}: ${msg.content}`)
          .join('\n');

      console.log('[UniversalChat] Executing prompt...');

      // Execute the prompt
      const { output } = await prompt({
          message,
          companyId,
          history: historyText
      });

      console.log('[UniversalChat] Prompt output:', output);

      if (!output) {
          throw new Error('Failed to generate response - output was null');
      }
      
      // Ensure data is always an array
      if (output.data === null || output.data === undefined) {
          output.data = [];
      }
      
      return output;
    } catch (error: any) {
      console.error('[UniversalChat] Error in flow:', error);
      console.error('[UniversalChat] Error stack:', error.stack);
      throw error;
    }
});
