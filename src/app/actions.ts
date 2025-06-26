'use server';

import { universalChatFlow } from '@/ai/flows/universal-chat';
import type { AssistantMessagePayload, Message } from '@/types';
import { createServerClient } from '@supabase/ssr';
import { z } from 'zod';
import { cookies } from 'next/headers';
import { APP_CONFIG } from '@/config/app-config';

/**
 * Transforms raw data from the AI/database into a format that our charting library can understand.
 * It's designed to be robust and not crash on unexpected data shapes.
 */
function transformDataForChart(data: any[] | null | undefined, chartType: string): any[] {
  if (!Array.isArray(data) || data.length === 0) {
    console.warn('[transformDataForChart] No data or invalid data provided for charting.');
    return [];
  }
  
  const firstItem = data[0];
  if (typeof firstItem !== 'object' || firstItem === null) {
      console.warn('[transformDataForChart] Data items are not objects, cannot transform for charting.');
      return [];
  }
  
  const keys = Object.keys(firstItem);
  if (keys.length === 0) {
    console.warn('[transformDataForChart] Data items have no keys, cannot transform for charting.');
    return [];
  }

  // Attempt to find the most likely candidates for name and value keys by looking for common substrings.
  const nameKey = keys.find(k => k.toLowerCase().includes('name') || k.toLowerCase().includes('category') || k.toLowerCase().includes('vendor')) || keys[0];
  const valueKey = keys.find(k => k.toLowerCase().includes('value') || k.toLowerCase().includes('total') || k.toLowerCase().includes('count') || k.toLowerCase().includes('quantity')) || (keys.length > 1 ? keys.find(k => k !== nameKey) : null);

  // If we can't determine a distinct value key, we can't create a meaningful chart.
  if (!valueKey) {
    console.warn(`[transformDataForChart] Could not determine a 'value' key for charting. Found keys: ${keys.join(', ')}`);
    return [];
  }

  console.log(`[transformDataForChart] Using nameKey: '${nameKey}', valueKey: '${valueKey}'`);
  
  return data.map(item => {
      const rawValue = item[valueKey];
      const numericValue = rawValue ? Number(rawValue) : 0;
      
      return {
          name: String(item[nameKey] || 'Unnamed'),
          value: isNaN(numericValue) ? 0 : numericValue,
      };
  }).filter(item => item.value !== 0 || chartType === 'line'); // Keep zero values only for line charts
}


// This schema now defines the full conversation history.
const UserMessagePayloadSchema = z.object({
  conversationHistory: z.array(z.object({
    role: z.enum(['user', 'assistant', 'system']),
    content: z.string(),
  })),
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

    // We check app_metadata first (set by trigger), then user_metadata as a fallback (set on signup).
    const companyId = user?.app_metadata?.company_id || user?.user_metadata?.company_id;
    if (!user || !companyId || typeof companyId !== 'string') {
        throw new Error("Application error: Could not determine company ID. The user may not be properly authenticated or configured.");
    }
    
    return companyId;
}

export async function handleUserMessage(
  payload: z.infer<typeof UserMessagePayloadSchema>
): Promise<AssistantMessagePayload> {
  // Validate the raw payload from the client.
  const { conversationHistory } = UserMessagePayloadSchema.parse(payload);
  
  try {
    const companyId = await getCompanyIdForCurrentUser();
    
    const response = await universalChatFlow({
      companyId,
      conversationHistory, // Pass the validated history directly
    });
    
    // Handle visualization suggestions from the AI
    if (response.visualization && response.visualization.type !== 'none' && response.data && response.data.length > 0) {
      
      if (['bar', 'pie', 'line'].includes(response.visualization.type)) {
          const transformedData = transformDataForChart(response.data, response.visualization.type);
          
          if (transformedData.length === 0) {
            console.log("[handleUserMessage] Data transformation resulted in an empty array, sending a text response instead.");
            return {
                id: Date.now().toString(),
                role: 'assistant' as const,
                content: response.response,
            };
          }

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
    
    if (error.message?.includes('Cannot define new actions at runtime')) {
      errorMessage = "A critical configuration error occurred in the AI flow. The application tried to define an AI tool dynamically, which is not allowed. This is a developer error that needs to be fixed in the code.";
    } else if (error.message?.includes('The AI model did not return a valid response object')) {
      errorMessage = "Sorry, the AI returned an unexpected response. This might be a temporary issue. Please try rephrasing your question."
    } else if (error.status === 'NOT_FOUND' || error.message?.includes('NOT_FOUND') || error.message?.includes('Model not found')) {
      errorMessage = 'It seems the AI model is not available. This is likely due to the "Generative Language API" not being enabled in your Google Cloud project, or the project is missing a billing account. Please enable the API and link a billing account, then try again.';
    } else if (error.message?.includes('API key not valid')) {
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
