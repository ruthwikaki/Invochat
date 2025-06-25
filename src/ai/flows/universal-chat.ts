'use server';

import { ai } from '@/ai/genkit';
import { z } from 'genkit';
import { supabaseAdmin } from '@/lib/supabase/admin';

// SQL execution tool
const executeSQLTool = ai.defineTool({
  name: 'executeSQL',
  description: `Execute SQL SELECT queries on the inventory database.
    Available tables and columns:
    - inventory: id, company_id, sku, name, description, category, quantity, cost, price, reorder_point, reorder_qty, supplier_name, warehouse_name, last_sold_date
    - vendors: id, company_id, vendor_name, contact_info, address, terms, account_number
    - companies: id, name
    
    IMPORTANT: Always include WHERE company_id = '{companyId}' in your queries for security.`,
  inputSchema: z.object({ 
    query: z.string().describe('The SQL SELECT query to execute'),
    companyId: z.string().describe('The company ID to filter by')
  }),
  outputSchema: z.array(z.any()),
}, async ({ query, companyId }) => {
  try {
    // Ensure the query includes the company_id filter
    if (!query.toLowerCase().includes('where')) {
      query = query + ` WHERE company_id = '${companyId}'`;
    } else if (!query.includes(companyId)) {
      query = query.replace(/where/i, `WHERE company_id = '${companyId}' AND`);
    }
    
    console.log('[SQL Tool] Executing:', query);
    
    const { data, error } = await supabaseAdmin.rpc('execute_dynamic_query', {
      query_text: query
    });
    
    if (error) {
      console.error('[SQL Tool] RPC error:', error);
      throw error;
    }
    
    // Check if the result contains an error
    if (data && typeof data === 'object' && 'error' in data) {
      console.error('[SQL Tool] Query error:', data.error);
      return [];
    }
    
    console.log('[SQL Tool] Result:', data);
    return data || [];
  } catch (error) {
    console.error('[SQL Tool] Execution error:', error);
    return [];
  }
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
  response: z.string().describe("Natural language response to the user"),
  data: z.array(z.any()).optional().describe("Data for visualization if needed"),
  visualization: z.object({
    type: z.enum(['table', 'bar', 'pie', 'line', 'none']),
    title: z.string().optional(),
    config: z.any().optional()
  }).optional()
});
export type UniversalChatOutput = z.infer<typeof UniversalChatOutputSchema>;


// Create the flow without using definePrompt (which is causing the error)
export const universalChatFlow = ai.defineFlow({
  name: 'universalChatFlow',
  inputSchema: UniversalChatInputSchema,
  outputSchema: UniversalChatOutputSchema,
}, async (input) => {
  const { message, companyId, conversationHistory = [] } = input;
  
  console.log('[UniversalChat] Starting flow with input:', input);
  
  try {
    // Direct AI generation with tools
    const { output } = await ai.generate({
      model: 'gemini-2.0-flash', // Specify the model
      tools: [executeSQLTool],
      prompt: `You are InvoChat, an intelligent inventory assistant. You help users understand their inventory data through natural conversation.

User's message: ${message}
Company ID for queries: ${companyId}

${conversationHistory.length > 0 ? `Previous conversation:
${conversationHistory.map(msg => `${msg.role}: ${msg.content}`).join('\n')}` : ''}

Instructions:
1. When users ask about inventory data, use the executeSQL tool to query the database
2. Always pass companyId: "${companyId}" when calling executeSQL
3. NEVER show SQL queries or technical details to the user
4. Provide insights and summaries, not just raw data
5. For inventory breakdown by category, use: SELECT category, COUNT(*) as count, SUM(quantity * cost) as value FROM inventory GROUP BY category
6. Suggest appropriate visualizations:
   - Use 'bar' for comparisons (like inventory by category)
   - Use 'pie' for distributions
   - Use 'table' for detailed lists
7. Be conversational and helpful

Remember: You're an intelligent assistant. When asked for charts or data, ACTUALLY query the database and return the data.

Return your response in this JSON format:
{
  "response": "Your natural language response",
  "data": [array of data if applicable],
  "visualization": {
    "type": "bar|pie|line|table|none",
    "title": "Chart title if applicable",
    "config": {}
  }
}`,
      output: {
        schema: UniversalChatOutputSchema
      }
    });
    
    console.log('[UniversalChat] AI output:', output);
    
    // The AI might return a string that needs to be parsed as JSON, but the schema should handle it.
    let result = output;
    
    // Ensure data is always an array
    if (!result.data || !Array.isArray(result.data)) {
      result.data = [];
    }
    
    return result;
    
  } catch (error: any) {
    console.error('[UniversalChat] Error in flow:', error);
    console.error('[UniversalChat] Error stack:', error.stack);
    
    // Fallback: Handle specific requests manually
    if (message.toLowerCase().includes('inventory') && message.toLowerCase().includes('chart')) {
      console.log('[UniversalChat] Fallback: Handling chart request manually');
      
      try {
        // Directly query the database
        const { data, error } = await supabaseAdmin.rpc('execute_dynamic_query', {
          query_text: `SELECT category, COUNT(*) as count, SUM(quantity * cost) as value FROM inventory WHERE company_id = '${companyId}' GROUP BY category`
        });
        
        console.log('[UniversalChat] Fallback query result:', { data, error });
        
        if (error) throw error;
        
        const chartData = data ? data.map((item: any) => ({
          name: item.category || 'Uncategorized',
          value: Math.round(Number(item.value || 0)),
          count: item.count || 0
        })) : [];
        
        return {
          response: `I've analyzed your inventory by category. ${chartData.length > 0 ? `You have ${chartData.length} different categories. The total inventory value is distributed across these categories.` : 'No inventory data found for your company.'}`,
          data: chartData,
          visualization: {
            type: 'bar' as const,
            title: 'Inventory Value by Category',
            config: {
              dataKey: 'value',
              nameKey: 'name'
            }
          }
        };
      } catch (fallbackError) {
        console.error('[UniversalChat] Fallback error:', fallbackError);
      }
    }
    
    throw error;
  }
});
