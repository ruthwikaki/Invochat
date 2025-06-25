'use server';

import { universalChatFlow } from '@/ai/flows/universal-chat';
import type { AssistantMessagePayload } from '@/types';
import { createServerClient } from '@supabase/ssr';
import { z } from 'zod';
import { cookies } from 'next/headers';

function transformDataForChart(data: any[], chartType: string) {
  if (!data || data.length === 0) return [];
  
  // For category breakdowns
  if (data[0].category !== undefined) {
    return data.map(item => ({
      name: item.category || 'Uncategorized',
      value: item.value ? Math.round(Number(item.value)) : 0,
      count: item.count || 0
    }));
  }
  
  // For other data structures, try to infer
  const keys = Object.keys(data[0]);
  const nameKey = keys.find(k => k.includes('name') || k.includes('category') || k.includes('item')) || keys[0];
  const valueKey = keys.find(k => k.includes('value') || k.includes('amount') || k.includes('quantity')) || keys[1];
  
  return data.map(item => ({
    name: item[nameKey] || 'Unknown',
    value: Number(item[valueKey]) || 0
  }));
}


const UserMessagePayloadSchema = z.object({
  message: z.string(),
  conversationHistory: z.array(z.object({
    role: z.enum(['user', 'assistant', 'system']),
    content: z.string()
  })).optional()
});

async function getCompanyIdForCurrentUser(): Promise<string> {
    const cookieStore = cookies();
    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          get(name: string) {
            return cookieStore.get(name)?.value;
          },
        },
      }
    );
    const { data: { user } } = await supabase.auth.getUser();

    const companyId = user?.app_metadata?.company_id;
    if (!user || !companyId || typeof companyId !== 'string') {
        throw new Error("Application error: Could not determine company ID. The user may not be properly authenticated or configured.");
    }
    
    return companyId;
}

export async function handleUserMessage(
  payload: z.infer<typeof UserMessagePayloadSchema>
): Promise<AssistantMessagePayload> {
  const { message, conversationHistory = [] } = UserMessagePayloadSchema.parse(payload);
  
  try {
    const companyId = await getCompanyIdForCurrentUser();
    
    const mappedHistory = conversationHistory
      .filter(m => m.role === 'user' || m.role === 'assistant')
      .map(m => ({
          role: m.role as 'user' | 'assistant',
          content: m.content
      }));

    // Let the AI handle everything
    const response = await universalChatFlow({
      message,
      companyId,
      conversationHistory: mappedHistory
    });
    
    // Handle visualization suggestions
    if (response.visualization && response.visualization.type !== 'none' && response.data && response.data.length > 0) {
      // Determine the appropriate component based on visualization type
      if (response.visualization.type === 'table') {
        const lowerCaseMessage = message.toLowerCase();
        // For tables showing dead stock
        if (lowerCaseMessage.includes('dead stock') || lowerCaseMessage.includes('not selling')) {
          return {
            id: Date.now().toString(),
            role: 'assistant' as const,
            content: response.response,
            component: 'DeadStockTable',
            props: { data: response.data }
          };
        }
        
        // For supplier tables
        if (lowerCaseMessage.includes('supplier') || lowerCaseMessage.includes('vendor')) {
          return {
            id: Date.now().toString(),
            role: 'assistant' as const,
            content: response.response,
            component: 'SupplierPerformanceTable',
            props: { data: response.data }
          };
        }
        
        // For reorder lists
        if (lowerCaseMessage.includes('reorder') || lowerCaseMessage.includes('order')) {
          return {
            id: Date.now().toString(),
            role: 'assistant' as const,
            content: response.response,
            component: 'ReorderList',
            props: { items: response.data }
          };
        }

        // Fallback for any other table
         return {
            id: Date.now().toString(),
            role: 'assistant',
            content: response.response,
            component: 'DataTable',
            props: { data: response.data }
          };
      }
      
      // For charts
      if (['bar', 'pie', 'line'].includes(response.visualization.type)) {
          const transformedData = transformDataForChart(response.data, response.visualization.type);
          return {
              id: Date.now().toString(),
              role: 'assistant' as const,
              content: response.response,
              component: 'DynamicChart',
              props: {
                chartType: response.visualization.type as 'bar' | 'pie' | 'line',
                title: response.visualization.title || 'Data Visualization',
                data: transformedData,
                config: {
                  dataKey: 'value',
                  nameKey: 'name',
                  xAxisKey: 'name'
                }
              }
          };
      }
    }
    
    // Default text response
    return {
      id: Date.now().toString(),
      role: 'assistant' as const,
      content: response.response
    };
    
  } catch (error: any) {
    console.error('Chat error:', error);
    let errorMessage = `Sorry, I encountered an error while processing your request. Please try again.`;
    if (error.message?.includes('API key not valid')) {
        errorMessage = 'It looks like your Google AI API key is invalid. Please make sure the `GOOGLE_API_KEY` in your `.env` file is correct and try again.'
    } else if (error.message?.includes('logged in')) {
        errorMessage = error.message;
    }
    return {
      id: Date.now().toString(),
      role: 'assistant',
      content: errorMessage,
    };
  }
}
