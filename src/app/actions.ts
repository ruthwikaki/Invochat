
'use server';

import { universalChatFlow } from '@/ai/flows/universal-chat';
import { UniversalChatOutputSchema } from '@/types/ai-schemas';
import type { Message, Conversation, DeadStockItem, SupplierPerformanceReport } from '@/types';
import { createServerClient } from '@supabase/ssr';
import { z } from 'zod';
import { cookies } from 'next/headers';
import { rateLimit } from '@/lib/redis';
import { trackAiQueryPerformance, trackEndpointPerformance } from '@/services/monitoring';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { config } from '@/config/app-config';
import { revalidatePath } from 'next/cache';
import { logger } from '@/lib/logger';
import { getErrorMessage, logError } from '@/lib/error-handler';

// Securely gets the user and company ID from the current session.
async function getAuthContext(): Promise<{ userId: string, companyId: string }> {
    const cookieStore = cookies();
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
            cookies: { get: (name: string) => cookieStore.get(name)?.value },
        }
    );
    const { data: { user }, error } = await supabase.auth.getUser();

    if (error || !user) {
        throw new Error('Authentication error: Could not get user.');
    }
    const companyId = user.app_metadata?.company_id;
    if (!companyId) {
        throw new Error('User is not associated with a company.');
    }
    return { userId: user.id, companyId };
}

export async function getConversations(): Promise<Conversation[]> {
    try {
        const { userId } = await getAuthContext();
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('conversations')
            .select('*')
            .eq('user_id', userId)
            .order('last_accessed_at', { ascending: false });

        if (error) {
            logError(error, { context: 'getConversations' });
            return [];
        }
        return data as Conversation[];
    } catch (error) {
        logError(error, { context: 'getAuthContext in getConversations' });
        return [];
    }
}

export async function getMessages(conversationId: string): Promise<Message[]> {
    try {
        const { userId } = await getAuthContext();
        const supabase = getServiceRoleClient();
        
        // Verify the user has access to this conversation
        const { error: accessError } = await supabase
            .from('conversations')
            .select('id')
            .eq('id', conversationId)
            .eq('user_id', userId)
            .single();

        if (accessError) {
             logError(accessError, { context: `Access denied or not found for convo ${conversationId}` });
             return [];
        }

        const { data, error } = await supabase
            .from('messages')
            .select('*')
            .eq('conversation_id', conversationId)
            .order('created_at', { ascending: true });
        
        if (error) {
            logError(error, { context: `getMessages for convo ${conversationId}` });
            return [];
        }

        await supabase.from('conversations').update({ last_accessed_at: new Date().toISOString() }).eq('id', conversationId);

        return data as Message[];
    } catch (error) {
        logError(error, { context: 'getAuthContext in getMessages' });
        return [];
    }
}


function transformDataForChart(data: Record<string, unknown>[] | null | undefined, chartType: string): Record<string, unknown>[] {
    if (!Array.isArray(data) || data.length === 0) return [];
    const firstItem = data[0];
    if (typeof firstItem !== 'object' || firstItem === null) return [];
    const keys = Object.keys(firstItem);
    if (keys.length < 2) return [];

    if (chartType === 'scatter') {
        // For scatter plots, ensure x and y exist and are numbers.
        return data.filter(p => typeof p.x === 'number' && typeof p.y === 'number');
    }
    
    // Auto-detect name and value keys based on common patterns and types.
    const valueKey = keys.find(k => k.toLowerCase().includes('value') || k.toLowerCase().includes('size') || k.toLowerCase().includes('total') || k.toLowerCase().includes('count') || k.toLowerCase().includes('quantity') || k.toLowerCase().includes('amount')) || keys.find(k => typeof firstItem[k] === 'number');
    const nameKey = keys.find(k => k !== valueKey && typeof firstItem[k] === 'string' && (k.toLowerCase().includes('name') || k.toLowerCase().includes('category') || k.toLowerCase().includes('vendor') || k.toLowerCase().includes('item'))) || keys.find(k => k !== valueKey);

    if (!valueKey || !nameKey) return [];

    const transformed = data.map((item) => {
        // Per-item validation: ensure it's a valid object with the required keys.
        if (typeof item !== 'object' || item === null || !(nameKey in item) || !(valueKey in item)) return null;
        
        // Coerce value to a number and check if it's valid.
        const rawValue = item[valueKey];
        const numericValue = parseFloat(String(rawValue));
        if (isNaN(numericValue)) return null;
        
        return { name: String(item[nameKey] ?? 'Unnamed'), value: numericValue };
    }).filter((item): item is { name: string; value: number } => item !== null);
    
    // For chart types that cannot handle negative values, filter them out.
    if (['pie', 'bar', 'treemap'].includes(chartType)) {
        return transformed.filter(item => item.value > 0);
    }
    
    return transformed;
}

function getFlowErrorMessage(error: unknown): string {
    const message = getErrorMessage(error);
    const status = (error as { status?: string })?.status || '';

    if (message.includes('Query timed out')) {
        return "The database query took too long to respond. This can happen with very complex questions. Please try simplifying your request.";
    } else if (message.includes('The database query failed')) {
        return "I tried to query the database, but the query failed. This may be because the AI generated an invalid SQL query or requested a non-existent column. Please try rephrasing your request.";
    } else if (message.includes('The generated query was invalid')) {
        return `For security, the AI-generated query was blocked. Reason: ${message.split('Reason: ')[1]}`;
    } else if (message.includes('The AI model did not return a valid final response object')) {
        return "The AI returned an unexpected or empty response. This might be a temporary issue. Please try again.";
    } else if (status === 'NOT_FOUND' || message.includes('NOT_FOUND') || message.includes('Model not found') || message.includes('INVALID_ARGUMENT')) {
        return `The AI model encountered an error. This is often due to the "Generative Language API" not being enabled in your Google Cloud project, an invalid API key, or a malformed request. Please check the System Health page for more details.`;
    } else if (message.includes('API key not valid')) {
        return 'Your Google AI API key is invalid. Please check the `GOOGLE_API_KEY` in your `.env` file and ensure it is correct.';
    } else if (message.includes('Your user session is invalid or not fully configured')) {
        return message;
    } else if (message.includes('violates not-null constraint')) {
        return 'A critical database error occurred while trying to save data. This may indicate an issue with the application setup.';
    } else if (message.includes('Rate limited')) {
        return 'You are sending messages too quickly. Please wait a moment before trying again.';
    }
    
    return `An unexpected error occurred. Please try again.`;
}

const UserMessagePayloadSchema = z.object({
  content: z.string(),
  conversationId: z.string().uuid().nullable(),
  source: z.string().optional(),
});

export async function handleUserMessage(
  payload: z.infer<typeof UserMessagePayloadSchema>
): Promise<{ conversationId?: string; newMessage?: Message; error?: string }> {
  const startTime = performance.now();
  let currentConversationId: string | null = null;
  
  try {
    const parsedPayload = UserMessagePayloadSchema.safeParse(payload);
    if (!parsedPayload.success) {
      return { error: "Invalid message payload." };
    }
    
    const { content: userQuery, source } = parsedPayload.data;
    currentConversationId = parsedPayload.data.conversationId;
    
    // This is now the single source of truth for auth context.
    const { userId, companyId } = await getAuthContext();
    
    const { limited } = await rateLimit(userId, 'ai_chat', 30, 60);
    if (limited) {
      logger.warn(`[Rate Limit] User ${userId} exceeded AI chat limit.`);
      throw new Error('Rate limited');
    }

    let historyForAI: { role: 'user' | 'assistant'; content: { text: string }[] }[] = [];

    if (!currentConversationId) {
        const title = source === 'analytics_page' 
            ? `Report: ${userQuery.substring(0, 40)}...`
            : userQuery.substring(0, 50);

        const { data: newConvo, error: convoError } = await getServiceRoleClient()
            .from('conversations')
            .insert({ user_id: userId, company_id: companyId, title })
            .select()
            .single();
        
        if (convoError) throw new Error(`Could not create conversation: ${convoError.message}`);
        currentConversationId = newConvo.id;
        historyForAI.push({ role: 'user', content: [{ text: userQuery }] });
    } else {
        const { data: history, error: historyError } = await getServiceRoleClient()
            .from('messages')
            .select('role, content')
            .eq('conversation_id', currentConversationId)
            // Note: The RLS policy on 'messages' table should enforce company_id check.
            .order('created_at', { ascending: false })
            .limit(config.ai.historyLimit);

        if (historyError) throw new Error("Could not fetch conversation history.");
        
        // Convert the database history to the format expected by the AI
        historyForAI = (history || [])
            .filter(msg => typeof msg.content === 'string')
            .reverse() // Reverse to get chronological order
            .map(msg => ({
                role: msg.role as 'user' | 'assistant',
                content: [{ text: msg.content! }] // Wrap content in the required structure
            }));
        // Add the current user query to the history
        historyForAI.push({ role: 'user', content: [{ text: userQuery }] });
    }


    await getServiceRoleClient().from('messages').insert({
        conversation_id: currentConversationId,
        company_id: companyId,
        role: 'user',
        content: userQuery,
    });
    
    const aiStartTime = performance.now();
    const flowResponse = await universalChatFlow({
      companyId,
      conversationHistory: historyForAI,
    });
    const aiEndTime = performance.now();
    await trackAiQueryPerformance(userQuery, aiEndTime - aiStartTime);
    
    const parsedResponse = UniversalChatOutputSchema.safeParse(flowResponse);
    if (!parsedResponse.success) {
      logError(parsedResponse.error, { context: "AI response validation error" });
      throw new Error('The AI returned data in an unexpected format.');
    }
    const responseData = parsedResponse.data;
    
    const assistantMessage: Omit<Message, 'id' | 'created_at'> = {
      conversation_id: currentConversationId,
      company_id: companyId,
      role: 'assistant',
      content: responseData.response,
      confidence: responseData.confidence,
      assumptions: responseData.assumptions,
    };
    
    // Handle custom components from tool calls
    if (responseData.toolName) {
        switch(responseData.toolName) {
            case 'getReorderSuggestions':
                assistantMessage.component = 'reorderList';
                assistantMessage.componentProps = { items: responseData.data };
                break;
            case 'getSupplierPerformanceReport':
                assistantMessage.component = 'supplierPerformanceTable';
                assistantMessage.componentProps = { data: responseData.data as SupplierPerformanceReport[] };
                break;
            case 'getDeadStockReport':
                assistantMessage.component = 'deadStockTable';
                assistantMessage.componentProps = { data: responseData.data as DeadStockItem[] };
                break;
        }
    } else if (responseData.visualization && responseData.visualization.type !== 'none' && Array.isArray(responseData.data) && responseData.data.length > 0) {
      // Handle generic visualizations from SQL queries
      const vizType = responseData.visualization.type;
      const vizTitle = responseData.visualization.title;
      let vizData = transformDataForChart(responseData.data, vizType);

      if (vizData && vizData.length > 0) {
        if (vizType === 'table') {
          assistantMessage.visualization = { type: 'table', data: responseData.data, config: { title: vizTitle || 'Data Table' }};
        } else if (['bar', 'pie', 'line', 'treemap', 'scatter'].includes(vizType)) {
            const firstItem = vizData[0] as Record<string, unknown>;
            const nameKey = (vizType === 'scatter') 
                ? 'name' 
                : Object.keys(firstItem).find(k => typeof firstItem[k] === 'string') || 'name';
            const dataKey = (vizType === 'scatter')
                ? 'y'
                : Object.keys(firstItem).find(k => typeof firstItem[k] === 'number') || 'value';

            assistantMessage.visualization = { 
              type: 'chart', 
              data: vizData, 
              config: { 
                chartType: vizType as any,
                title: vizTitle || 'Data Visualization', 
                dataKey: dataKey, 
                nameKey: nameKey,
                xAxisKey: (vizType === 'scatter') ? 'x' : nameKey,
                yAxisKey: (vizType === 'scatter') ? 'y' : dataKey,
              }
            };
        }
      }
    }
    
    const { data: savedAssistantMessage, error: saveMsgError } = await getServiceRoleClient()
        .from('messages')
        .insert(assistantMessage)
        .select()
        .single();
    
    if (saveMsgError) {
      logError(saveMsgError, { context: 'Error saving assistant message' });
      throw new Error(`Could not save assistant message: ${saveMsgError.message}`);
    }
    
    if (parsedPayload.data.conversationId) {
        revalidatePath(`/chat?id=${parsedPayload.data.conversationId}`);
    } else {
        revalidatePath('/chat');
    }
    
    if (source === 'analytics_page') {
      revalidatePath('/analytics');
    }

    return { conversationId: currentConversationId, newMessage: savedAssistantMessage as Message };
    
  } catch (error) {
    logError(error, {
        payload,
        conversationId: currentConversationId,
        context: 'handleUserMessage'
    });
    return { error: getFlowErrorMessage(error) };
  } finally {
      const endTime = performance.now();
      await trackEndpointPerformance('handleUserMessage', endTime - startTime);
  }
}
