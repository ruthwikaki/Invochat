'use server';

import { universalChatFlow } from '@/ai/flows/universal-query';
import type { AssistantMessagePayload } from '@/types';
import { createServerClient } from '@supabase/ssr';
import { z } from 'zod';
import { cookies } from 'next/headers';

const actionResponseSchema = z.object({
  id: z.string(),
  role: z.literal('assistant'),
  content: z.string().optional(),
  component: z.enum(['DataTable', 'DynamicChart']).optional(),
  props: z.any().optional(),
}) satisfies z.ZodType<AssistantMessagePayload>;


const UserMessagePayloadSchema = z.object({
  message: z.string(),
});

type UserMessagePayload = z.infer<typeof UserMessagePayloadSchema>;


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

function extractTitle(text: string): string {
  return text.split('\n')[0] || 'Chart';
}

function inferChartConfig(data: any[]): any {
  if (!data || data.length === 0) {
    return { dataKey: 'value', nameKey: 'name' };
  }
  const firstItem = data[0];
  const keys = Object.keys(firstItem);
  
  const nameKey = keys.find(k => ['name', 'label', 'category', 'date'].includes(k.toLowerCase())) || keys[0];
  const dataKey = keys.find(k => ['value', 'count', 'quantity', 'total'].includes(k.toLowerCase())) || keys.find(k => typeof firstItem[k] === 'number') || keys[1];

  return {
    dataKey,
    nameKey,
    xAxisKey: nameKey
  };
}


export async function handleUserMessage(
  payload: UserMessagePayload
): Promise<AssistantMessagePayload> {
  const { message } = UserMessagePayloadSchema.parse(payload);
  
  try {
    const companyId = await getCompanyIdForCurrentUser();
    
    // You'll need to implement passing conversation history from the client
    const conversationHistory: any[] = []; 
    
    // Let the AI handle everything
    const flowResult = await universalChatFlow({
      message,
      companyId,
      conversationHistory
    });
    
    const content = flowResult.response;
    const data = flowResult.data;
    const visualization = flowResult.suggestedVisualization;

    if (visualization && data && data.length > 0) {
      switch (visualization) {
        case 'bar':
        case 'pie':
        case 'line':
          return actionResponseSchema.parse({
            id: Date.now().toString(),
            role: 'assistant',
            content: content,
            component: 'DynamicChart',
            props: {
              chartType: visualization,
              title: extractTitle(content),
              data: data,
              config: inferChartConfig(data)
            }
          });
        case 'table':
          return actionResponseSchema.parse({
            id: Date.now().toString(),
            role: 'assistant',
            content: content,
            component: 'DataTable',
            props: { data: data }
          });
        default:
          // Fallthrough for 'none'
          break;
      }
    }
    
    // Default case: just return the text response
    return actionResponseSchema.parse({
      id: Date.now().toString(),
      role: 'assistant',
      content: content
    });
    
  } catch (error: any) {
    console.error('Chat error:', error);
    let errorMessage = `Sorry, I encountered an error while processing your request: ${error.message}. Please try again.`;
    if (error.message?.includes('API key not valid')) {
        errorMessage = 'It looks like your Google AI API key is invalid. Please make sure the `GOOGLE_API_KEY` in your `.env` file is correct and try again.'
    }
    return actionResponseSchema.parse({
      id: Date.now().toString(),
      role: 'assistant',
      content: errorMessage,
    });
  }
}
