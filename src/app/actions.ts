
'use server';

import { universalChatFlow } from '@/ai/flows/universal-chat';
import { UniversalChatOutputSchema } from '@/types/ai-schemas';
import type { Message } from '@/types';
import { createServerClient } from '@supabase/ssr';
import { z } from 'zod';
import { cookies } from 'next/headers';

/**
 * Transforms raw data from the AI/database into a format that our charting library can understand.
 * This function has been rewritten to be robust and handle unexpected data shapes gracefully.
 */
function transformDataForChart(data: any[] | null | undefined, chartType: string): { name: string; value: number }[] {
    if (!Array.isArray(data) || data.length === 0) {
        return [];
    }
    const firstItem = data[0];
    if (typeof firstItem !== 'object' || firstItem === null) {
        return [];
    }
    const keys = Object.keys(firstItem);
    if (keys.length < 2) {
        return [];
    }
    
    // Find the most likely "name" and "value" keys based on common patterns.
    const nameKey = keys.find(k => typeof firstItem[k] === 'string' && (k.toLowerCase().includes('name') || k.toLowerCase().includes('category') || k.toLowerCase().includes('vendor') || k.toLowerCase().includes('item'))) || keys[0];
    const valueKey = keys.find(k => k !== nameKey && typeof firstItem[k] === 'number') 
                     || keys.find(k => k !== nameKey && (k.toLowerCase().includes('value') || k.toLowerCase().includes('total') || k.toLowerCase().includes('count') || k.toLowerCase().includes('quantity') || k.toLowerCase().includes('amount')));

    if (!valueKey) {
        console.warn('[transformDataForChart] Could not determine a numeric value key for the chart.');
        return [];
    }

    const transformed = data.map((item) => {
        // Validate each item in the array
        if (typeof item !== 'object' || item === null || !(nameKey in item) || !(valueKey in item)) {
            return null;
        }
        
        const rawValue = item[valueKey];
        const numericValue = parseFloat(rawValue);
        
        // Ensure the value is a valid number
        if (isNaN(numericValue)) {
            return null;
        }
        
        return {
            name: String(item[nameKey] ?? 'Unnamed'),
            value: numericValue,
        };
    }).filter((item): item is { name: string; value: number } => item !== null); // Filter out any nulls
    
    // For pie and bar charts, it doesn't make sense to show zero-value items.
    if (chartType === 'pie' || chartType === 'bar') {
        return transformed.filter(item => item.value !== 0);
    }
    
    return transformed;
}

const UserMessagePayloadSchema = z.object({
  conversationHistory: z.array(z.object({
    id: z.string().optional(), // Make ID optional as it's not needed by AI
    role: z.enum(['user', 'assistant', 'system']),
    content: z.string(),
    timestamp: z.number().optional(), // Make timestamp optional
    visualization: z.any().optional(),
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
    const companyId = user?.app_metadata?.company_id || user?.user_metadata?.company_id;
    if (!user || !companyId || typeof companyId !== 'string') {
        throw new Error("Application error: Could not determine company ID. The user may not be properly authenticated or configured.");
    }
    return companyId;
}

function getErrorMessage(error: any): string {
    let errorMessage = `An unexpected error occurred. Please try again.`;
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
    return errorMessage;
}

export async function handleUserMessage(
  payload: z.infer<typeof UserMessagePayloadSchema>
): Promise<Message> {
  const parsedPayload = UserMessagePayloadSchema.safeParse(payload);
  if (!parsedPayload.success) {
    return { 
      id: Date.now().toString(), 
      role: 'assistant', 
      content: "There was a problem with the message format.",
      timestamp: Date.now()
    };
  }
  
  const { conversationHistory } = parsedPayload.data;
  
  try {
    const companyId = await getCompanyIdForCurrentUser();
    
    // Convert Message[] to the format needed by AI
    const historyForAI = conversationHistory.map(msg => ({
      role: msg.role as 'user' | 'assistant',
      content: msg.content // This is always a string now
    }));
    
    const flowResponse = await universalChatFlow({
      companyId,
      conversationHistory: historyForAI,
    });
    
    const parsedResponse = UniversalChatOutputSchema.safeParse(flowResponse);
    if (!parsedResponse.success) {
      console.error("AI response validation error:", parsedResponse.error);
      throw new Error('The AI returned data in an unexpected format. Please check the console for details.');
    }
    
    const response = parsedResponse.data;
    
    // Create the message with visualization data separated
    const message: Message = {
      id: Date.now().toString(),
      role: 'assistant',
      content: response.response,
      timestamp: Date.now(),
    };
    
    // Add visualization if suggested by the AI
    if (response.visualization && response.visualization.type !== 'none' && Array.isArray(response.data) && response.data.length > 0) {
      if (response.visualization.type === 'table') {
        message.visualization = {
          type: 'table',
          data: response.data,
          config: {
            title: response.visualization.title || 'Data Table'
          }
        };
      } else if (['bar', 'pie', 'line'].includes(response.visualization.type)) {
        const transformedData = transformDataForChart(response.data, response.visualization.type);
        if (transformedData.length > 0) {
          message.visualization = {
            type: 'chart',
            data: transformedData,
            config: {
              chartType: response.visualization.type as 'bar' | 'pie' | 'line',
              title: response.visualization.title || 'Data Visualization',
              dataKey: 'value',
              nameKey: 'name',
              xAxisKey: 'name'
            }
          };
        }
      }
    }
    
    return message;
    
  } catch (error: any) {
    console.error('Chat error:', error);
    return {
      id: Date.now().toString(),
      role: 'assistant',
      content: getErrorMessage(error),
      timestamp: Date.now()
    };
  }
}
