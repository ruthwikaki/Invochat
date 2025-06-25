'use server';

import { universalChatFlow } from '@/ai/flows/universal-chat';
import type { AssistantMessagePayload } from '@/types';
import { createServerClient } from '@supabase/ssr';
import { z } from 'zod';
import { cookies } from 'next/headers';

/**
 * Transforms raw data from the AI/database into a format that our charting library can understand.
 * It tries to intelligently guess the correct keys for names and values.
 */
function transformDataForChart(data: any[], chartType: string) {
  if (!data || data.length === 0) return [];
  
  // Standardize keys for common queries like category breakdowns.
  const standardizedData = data.map(item => ({
      name: item.category || item.name || item.vendor_name || 'Unnamed',
      value: item.total_value || item.value || item.total_sales || item.count || item.quantity || 0,
      ...item
  }));

  // For category breakdowns specifically, ensure value is numeric
  if (standardizedData[0].name && standardizedData[0].value) {
    return standardizedData.map(item => ({
      name: item.name,
      value: Math.round(Number(item.value) || 0),
      count: item.count || 0
    }));
  }
  
  // Generic fallback for other data structures.
  const keys = Object.keys(standardizedData[0]);
  const nameKey = keys.find(k => k.includes('name') || k.includes('category') || k.includes('item')) || keys[0];
  const valueKey = keys.find(k => k.includes('value') || k.includes('amount') || k.includes('quantity') || k.includes('total')) || keys[1];
  
  return standardizedData.map(item => ({
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
      // Filter out system messages and initial empty messages
      .filter(m => (m.role === 'user' || m.role === 'assistant') && m.content)
      .map(m => ({
          role: m.role as 'user' | 'assistant',
          content: m.content
      }));

    // Let the new universal AI flow handle everything
    const response = await universalChatFlow({
      message,
      companyId,
      conversationHistory: mappedHistory
    });
    
    // Handle visualization suggestions from the AI
    if (response.visualization && response.visualization.type !== 'none' && response.data && response.data.length > 0) {
      
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
      
      // The AI can suggest a table for any kind of list data.
      if (response.visualization.type === 'table') {
         return {
            id: Date.now().toString(),
            role: 'assistant',
            content: response.response,
            component: 'DataTable',
            props: { data: response.data }
          };
      }
    }
    
    // If no visualization, or an empty one, return a standard text response.
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
    } else if (error.message?.includes('authenticated or configured')) {
        errorMessage = error.message;
    }
    return {
      id: Date.now().toString(),
      role: 'assistant',
      content: errorMessage,
    };
  }
}
