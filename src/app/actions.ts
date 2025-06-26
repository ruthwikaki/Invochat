
'use server';

import { universalChatFlow } from '@/ai/flows/universal-chat';
import { UniversalChatOutputSchema } from '@/types/ai-schemas';
import type { AssistantMessagePayload, Message } from '@/types';
import { createServerClient } from '@supabase/ssr';
import { z } from 'zod';
import { cookies } from 'next/headers';
import { APP_CONFIG } from '@/config/app-config';

/**
 * Transforms raw data from the AI/database into a format that our charting library can understand.
 * This function has been rewritten to be robust and handle unexpected data shapes gracefully.
 */
function transformDataForChart(data: any[] | null | undefined, chartType: string): { name: string; value: number }[] {
    // 1. Validate input data
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
    if (keys.length < 2) {
        console.warn(`[transformDataForChart] Data items have fewer than 2 keys, cannot generate a meaningful chart. Found keys: ${keys.join(', ')}.`);
        return [];
    }
    
    // 2. More robust key finding logic
    const nameKey = keys.find(k => k.toLowerCase().includes('name') || k.toLowerCase().includes('category') || k.toLowerCase().includes('vendor') || k.toLowerCase().includes('item')) || keys[0];
    const valueKey = keys.find(k => k !== nameKey && (typeof firstItem[k] === 'number' || !isNaN(Number(firstItem[k]))))
                     || keys.find(k => k !== nameKey && (k.toLowerCase().includes('value') || k.toLowerCase().includes('total') || k.toLowerCase().includes('count') || k.toLowerCase().includes('quantity') || k.toLowerCase().includes('amount')));

    if (!valueKey) {
        console.warn(`[transformDataForChart] Could not automatically determine a numeric 'value' key for charting from keys: ${keys.join(', ')}.`);
        return [];
    }

    console.log(`[transformDataForChart] Using nameKey: '${nameKey}', valueKey: '${valueKey}'`);

    // 3. Map and sanitize data
    const transformed = data.map((item, index) => {
        if (typeof item !== 'object' || item === null) return null;

        const rawValue = item[valueKey];
        // Use parseFloat for better handling of decimal values
        const numericValue = parseFloat(rawValue);

        // Ensure value is a valid number
        if (isNaN(numericValue)) {
            console.warn(`[transformDataForChart] Row ${index} has a non-numeric value for key '${valueKey}':`, rawValue);
            return null;
        }

        return {
            name: String(item[nameKey] ?? `Category ${index + 1}`),
            value: numericValue,
        };
    }).filter((item): item is { name: string; value: number } => item !== null);

    // 4. Filter out zero values for certain chart types
    if (chartType === 'pie' || chartType === 'bar') {
        return transformed.filter(item => item.value !== 0);
    }

    return transformed;
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
  const parsedPayload = UserMessagePayloadSchema.safeParse(payload);
  if (!parsedPayload.success) {
      return { id: Date.now().toString(), role: 'assistant', content: "There was a problem with the message format." };
  }
  const { conversationHistory } = parsedPayload.data;
  
  try {
    const companyId = await getCompanyIdForCurrentUser();
    
    const flowResponse = await universalChatFlow({
      companyId,
      conversationHistory,
    });
    
    // **Robust Validation:** Safely parse the AI's output.
    const parsedResponse = UniversalChatOutputSchema.safeParse(flowResponse);

    if (!parsedResponse.success) {
      console.error('Invalid AI response structure:', parsedResponse.error);
      throw new Error('The AI returned data in an unexpected format. Please try again.');
    }
    const response = parsedResponse.data;
    
    // Handle visualization suggestions from the AI
    if (response.visualization && response.visualization.type !== 'none' && response.data && response.data.length > 0) {
      
      if (['bar', 'pie', 'line'].includes(response.visualization.type)) {
          const transformedData = transformDataForChart(response.data, response.visualization.type);
          
          if (transformedData.length === 0) {
            console.log("[handleUserMessage] Data transformation for chart resulted in an empty array, sending a text response instead.");
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
                  dataKey: 'value', // Standardized key after transformation
                  nameKey: 'name',   // Standardized key after transformation
                  xAxisKey: 'name'  // Standardized key after transformation
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
    let errorMessage = `An unexpected error occurred. Please try again.`;

    // Provide more specific, helpful error messages for common issues.
    if (error.message?.includes('Query timed out')) {
      errorMessage = error.message;
    } else if (error.message?.includes('Query failed with error')) {
      errorMessage = "I tried to query the database, but the query failed. The AI may have generated an invalid SQL query or requested a non-existent column. Please try rephrasing your request.";
    } else if (error.message?.includes('Query is insecure')) {
      errorMessage = "The AI generated a query that was deemed insecure and was blocked. Please try your request again.";
    } else if (error.message?.includes('The AI model did not return a valid response object')) {
      errorMessage = "The AI returned an unexpected or empty response. This might be a temporary issue with the model. Please try again."
    } else if (error.status === 'NOT_FOUND' || error.message?.includes('NOT_FOUND') || error.message?.includes('Model not found')) {
      errorMessage = 'The configured AI model is not available. This is often due to the "Generative Language API" not being enabled in your Google Cloud project, or the project is missing a billing account.';
    } else if (error.message?.includes('API key not valid')) {
        errorMessage = 'Your Google AI API key is invalid. Please check the `GOOGLE_API_KEY` in your `.env` file.'
    } else if (error.message?.includes('authenticated or configured')) {
        errorMessage = error.message; // Pass auth error message directly to user.
    } else if (error.message?.includes('companyId was not found')) {
        errorMessage = 'A critical security error occurred. The AI tool could not access your company ID. Please try signing out and in again.'
    }

    return {
      id: Date.now().toString(),
      role: 'assistant',
      content: errorMessage,
    };
  }
}
