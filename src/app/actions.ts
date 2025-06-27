
'use server';

import { universalChatFlow } from '@/ai/flows/universal-chat';
import { UniversalChatOutputSchema } from '@/types/ai-schemas';
import type { Message, Conversation } from '@/types';
import { createServerClient } from '@supabase/ssr';
import { z } from 'zod';
import { cookies } from 'next/headers';
import { redisClient, isRedisEnabled } from '@/lib/redis';
import crypto from 'crypto';
import { trackAiQueryPerformance, incrementCacheHit, incrementCacheMiss } from '@/services/monitoring';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { APP_CONFIG } from '@/config/app-config';
import { revalidatePath } from 'next/cache';

function getServiceRoleClient() {
    if (!supabaseAdmin) {
        throw new Error('Database admin client is not configured.');
    }
    return supabaseAdmin;
}

async function getAuthContext(): Promise<{ userId: string, companyId: string }> {
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
    // Use app_metadata as the source of truth, set by the trigger
    const companyId = user?.app_metadata?.company_id;
    if (!user || !companyId) {
        throw new Error("Authentication error: User or company not found.");
    }
    return { userId: user.id, companyId };
}

/**
 * Fetches all conversations for the currently authenticated user.
 */
export async function getConversations(): Promise<Conversation[]> {
    try {
        const { userId, companyId } = await getAuthContext();
        const supabase = getServiceRole-client();
        const { data, error } = await supabase
            .from('conversations')
            .select('*')
            .eq('user_id', userId)
            .eq('company_id', companyId)
            .order('last_accessed_at', { ascending: false });

        if (error) {
            console.error("Error fetching conversations:", error);
            return [];
        }
        return data as Conversation[];
    } catch (error) {
        console.error("Failed to get auth context in getConversations:", error);
        return [];
    }
}

/**
 * Fetches all messages for a given conversation ID, ensuring the user has access.
 */
export async function getMessages(conversationId: string): Promise<Message[]> {
    try {
        const { userId, companyId } = await getAuthContext();
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('messages')
            .select('*')
            .eq('conversation_id', conversationId)
            .eq('company_id', companyId) // Security check
            .order('created_at', { ascending: true });
        
        if (error) {
            console.error(`Error fetching messages for convo ${conversationId}:`, error);
            return [];
        }

        // Also update the last_accessed_at timestamp for the conversation
        await supabase.from('conversations').update({ last_accessed_at: new Date().toISOString() }).eq('id', conversationId);

        return data as Message[];
    } catch (error) {
        console.error("Failed to get auth context in getMessages:", error);
        return [];
    }
}


function transformDataForChart(data: any[] | null | undefined, chartType: string): { name: string; value: number }[] {
    if (!Array.isArray(data) || data.length === 0) return [];
    const firstItem = data[0];
    if (typeof firstItem !== 'object' || firstItem === null) return [];
    const keys = Object.keys(firstItem);
    if (keys.length < 2) return [];
    
    const nameKey = keys.find(k => typeof firstItem[k] === 'string' && (k.toLowerCase().includes('name') || k.toLowerCase().includes('category') || k.toLowerCase().includes('vendor') || k.toLowerCase().includes('item'))) || keys[0];
    const valueKey = keys.find(k => k !== nameKey && typeof firstItem[k] === 'number') || keys.find(k => k !== nameKey && (k.toLowerCase().includes('value') || k.toLowerCase().includes('total') || k.toLowerCase().includes('count') || k.toLowerCase().includes('quantity') || k.toLowerCase().includes('amount')));

    if (!valueKey) return [];

    const transformed = data.map((item) => {
        if (typeof item !== 'object' || item === null || !(nameKey in item) || !(valueKey in item)) return null;
        const rawValue = item[valueKey];
        const numericValue = parseFloat(rawValue);
        if (isNaN(numericValue)) return null;
        
        return { name: String(item[nameKey] ?? 'Unnamed'), value: numericValue };
    }).filter((item): item is { name: string; value: number } => item !== null);
    
    if (chartType === 'pie' || chartType === 'bar') {
        return transformed.filter(item => item.value !== 0);
    }
    
    return transformed;
}

function getErrorMessage(error: any): string {
    let errorMessage = `An unexpected error occurred. Please try again.`;
    if (error.message?.includes('Query timed out')) errorMessage = error.message;
    else if (error.message?.includes('The database query failed')) errorMessage = "I tried to query the database, but the query failed. The AI may have generated an invalid SQL query or requested a non-existent column. Please try rephrasing your request.";
    else if (error.message?.includes('The generated query was invalid')) errorMessage = "The AI generated a query that was deemed insecure and was blocked. Please try your request again.";
    else if (error.message?.includes('The AI model did not return a valid final response object')) errorMessage = "The AI returned an unexpected or empty response. This might be a temporary issue with the model. Please try again."
    else if (error.status === 'NOT_FOUND' || error.message?.includes('NOT_FOUND') || error.message?.includes('Model not found')) errorMessage = 'The configured AI model is not available. This is often due to the "Generative Language API" not being enabled in your Google Cloud project, or the project is missing a billing account.';
    else if (error.message?.includes('API key not valid')) errorMessage = 'Your Google AI API key is invalid. Please check the `GOOGLE_API_KEY` in your `.env` file.'
    else if (error.message?.includes('authenticated or configured')) errorMessage = error.message;
    return errorMessage;
}

const UserMessagePayloadSchema = z.object({
  content: z.string(),
  conversationId: z.string().uuid().nullable(),
  source: z.string().optional(),
});

export async function handleUserMessage(
  payload: z.infer<typeof UserMessagePayloadSchema>
): Promise<{ conversationId?: string; newMessage?: Message; error?: string }> {
  const parsedPayload = UserMessagePayloadSchema.safeParse(payload);
  if (!parsedPayload.success) {
    return { error: "Invalid message payload." };
  }
  
  const { content: userQuery, source } = parsedPayload.data;
  const initialConversationId = parsedPayload.data.conversationId;
  const supabase = getServiceRoleClient();

  try {
    const { userId, companyId } = await getAuthContext();
    let currentConversationId = initialConversationId;
    let historyForAI: { role: 'user' | 'assistant'; content: string }[] = [];

    // Step 1: Find or Create Conversation
    if (!currentConversationId) {
        const title = source === 'analytics_page' 
            ? `Report: ${userQuery.substring(0, 40)}...`
            : userQuery.substring(0, 50);

        const { data: newConvo, error: convoError } = await supabase
            .from('conversations')
            .insert({ user_id: userId, company_id: companyId, title })
            .select()
            .single();
        
        if (convoError) throw new Error(`Could not create conversation: ${convoError.message}`);
        currentConversationId = newConvo.id;
    } else {
        // If conversation exists, fetch its history for AI context
        const { data: history, error: historyError } = await supabase
            .from('messages')
            .select('role, content')
            .eq('conversation_id', currentConversationId)
            .order('created_at', { ascending: false })
            .limit(APP_CONFIG.ai.historyLimit);

        if (historyError) throw new Error("Could not fetch conversation history.");
        historyForAI = (history || []).reverse().map(msg => ({
            role: msg.role as 'user' | 'assistant',
            content: msg.content
        }));
    }

    if (!currentConversationId) {
        throw new Error("Failed to create or identify a conversation.");
    }

    // Step 2: Save the user's message
    await supabase.from('messages').insert({
        conversation_id: currentConversationId,
        company_id: companyId,
        role: 'user',
        content: userQuery,
    });
    
    // Add the new user message to the history for the AI call
    historyForAI.push({ role: 'user', content: userQuery });
    
    // Step 3: Call the AI flow (check cache first)
    let flowResponse;
    const queryHash = crypto.createHash('sha256').update(userQuery.toLowerCase().trim()).digest('hex');
    const cacheKey = `company:${companyId}:query:${queryHash}`;

    if (isRedisEnabled) {
        const cachedResponse = await redisClient.get(cacheKey);
        if (cachedResponse) {
            console.log(`[Cache] HIT for AI query: ${cacheKey}`);
            await incrementCacheHit('ai_query');
            flowResponse = JSON.parse(cachedResponse);
        } else {
            console.log(`[Cache] MISS for AI query: ${cacheKey}`);
            await incrementCacheMiss('ai_query');
        }
    }

    if (!flowResponse) {
        const startTime = performance.now();
        flowResponse = await universalChatFlow({
          companyId,
          conversationHistory: historyForAI,
        });
        const endTime = performance.now();
        await trackAiQueryPerformance(userQuery, endTime - startTime);
    }
    
    const parsedResponse = UniversalChatOutputSchema.safeParse(flowResponse);
    if (!parsedResponse.success) {
      console.error("AI response validation error:", parsedResponse.error);
      throw new Error('The AI returned data in an unexpected format.');
    }
    const responseData = parsedResponse.data;
    
    // Step 4: Construct and save the assistant's message
    const assistantMessage: Omit<Message, 'id' | 'created_at'> = {
      conversation_id: currentConversationId,
      role: 'assistant',
      content: responseData.response,
      confidence: responseData.confidence,
      assumptions: responseData.assumptions,
    };
    
    if (responseData.visualization && responseData.visualization.type !== 'none' && Array.isArray(responseData.data) && responseData.data.length > 0) {
      if (responseData.visualization.type === 'table') {
        assistantMessage.visualization = { type: 'table', data: responseData.data, config: { title: responseData.visualization.title || 'Data Table' }};
      } else if (['bar', 'pie', 'line'].includes(responseData.visualization.type)) {
        const transformedData = transformDataForChart(responseData.data, responseData.visualization.type);
        if (transformedData.length > 0) {
          assistantMessage.visualization = { type: 'chart', data: transformedData, config: { chartType: responseData.visualization.type as 'bar' | 'pie' | 'line', title: responseData.visualization.title || 'Data Visualization', dataKey: 'value', nameKey: 'name', xAxisKey: 'name' }};
        }
      }
    }
    
    const { data: savedAssistantMessage, error: saveMsgError } = await supabase
        .from('messages')
        .insert(assistantMessage)
        .select()
        .single();
    
    if (saveMsgError) throw new Error(`Could not save assistant message: ${saveMsgError.message}`);
    
    // Step 5: Cache the successful result in Redis if it wasn't a cache hit
    if (isRedisEnabled && !redisClient.get(cacheKey) && assistantMessage.content && !assistantMessage.content.toLowerCase().includes('error')) {
        try {
            await redisClient.set(cacheKey, JSON.stringify(flowResponse), 'EX', 3600); // Cache for 1 hour
            console.log(`[Cache] SET for AI query: ${cacheKey}`);
        } catch (e) {
            console.error(`[Redis] Error setting cached query for ${cacheKey}:`, e);
        }
    }
    
    // Revalidate the chat path to trigger UI updates
    revalidatePath('/chat');
    if (source === 'analytics_page') {
      revalidatePath('/analytics');
    }

    return { conversationId: currentConversationId, newMessage: savedAssistantMessage as Message };
    
  } catch (error: any) {
    console.error('Chat error:', error);
    return { error: getErrorMessage(error) };
  }
}

    