

'use server';

import type { Message } from '@/types';
import { universalChatFlow } from '@/ai/flows/universal-chat';
import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { rateLimit } from '@/lib/redis';
import { config } from '@/config/app-config';
import { getAuthContext } from './data-actions';

async function saveConversation(companyId: string, title: string) {
    const cookieStore = cookies();
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

    if (!supabaseUrl || !supabaseAnonKey) {
        throw new Error("Supabase environment variables are not set for API route.");
    }

    const supabase = createServerClient(
        supabaseUrl,
        supabaseAnonKey,
        {
          cookies: { get: (name: string) => cookieStore.get(name)?.value },
        }
    );

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
        throw new Error('User not authenticated.');
    }
    
    const { data, error } = await supabase
        .from('conversations')
        .insert({
            user_id: user.id,
            company_id: companyId,
            title: title
        })
        .select('id')
        .single();

    if (error) {
        logError(error, { context: 'Failed to save new conversation' });
        throw new Error('Could not save conversation to the database.');
    }
    return data.id;
}


async function saveMessage(message: Omit<Message, 'id' | 'created_at'>) {
    const cookieStore = cookies();
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (!supabaseUrl || !supabaseAnonKey) {
        throw new Error("Supabase environment variables are not set.");
    }
    const supabase = createServerClient(
        supabaseUrl,
        supabaseAnonKey,
        {
          cookies: { get: (name: string) => cookieStore.get(name)?.value },
        }
    );
    const { error } = await supabase.from('messages').insert(message);
    if (error) {
        logError(error, { context: 'Failed to save message' });
    }
}

export async function getConversations() {
    try {
        const cookieStore = cookies();
        const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
        const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
        if (!supabaseUrl || !supabaseAnonKey) {
            throw new Error("Supabase environment variables are not set.");
        }
        const supabase = createServerClient(
            supabaseUrl,
            supabaseAnonKey,
            {
            cookies: { get: (name: string) => cookieStore.get(name)?.value },
            }
        );
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) return [];

        const { data, error } = await supabase
            .from('conversations')
            .select('*')
            .eq('user_id', user.id)
            .order('last_accessed_at', { ascending: false });

        if (error) {
            logError(error, { context: 'Failed to get conversations' });
            return [];
        }
        return data || [];
    } catch(e) {
        logError(e, { context: 'getConversations action' });
        return [];
    }
}

export async function getMessages(conversationId: string) {
    try {
        const cookieStore = cookies();
        const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
        const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
        if (!supabaseUrl || !supabaseAnonKey) {
            throw new Error("Supabase environment variables are not set.");
        }
        const supabase = createServerClient(
            supabaseUrl,
            supabaseAnonKey,
            {
            cookies: { get: (name: string) => cookieStore.get(name)?.value },
            }
        );
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) return [];

        await supabase
            .from('conversations')
            .update({ last_accessed_at: new Date().toISOString() })
            .eq('id', conversationId);

        const { data, error } = await supabase
            .from('messages')
            .select('*')
            .eq('conversation_id', conversationId)
            .order('created_at', { ascending: true });
        
        if (error) {
            logError(error, { context: `Failed to get messages for conversation ${conversationId}` });
            return [];
        }
        return data || [];
    } catch (e) {
        logError(e, { context: `getMessages action for conversation ${conversationId}` });
        return [];
    }
}


export async function handleUserMessage({ content, conversationId }: { content: string, conversationId: string | null }) {
    try {
        const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
        const { limited } = await rateLimit(ip, 'ai_chat', config.ratelimit.ai, 60, true);
        if (limited) {
            return { error: 'You have reached the request limit. Please try again in a minute.' };
        }

        const { companyId } = await getAuthContext();
        
        let currentConversationId = conversationId;
        if (!currentConversationId) {
            const newTitle = content.length > 50 ? `${content.substring(0, 50)}...` : content;
            currentConversationId = await saveConversation(companyId, newTitle);
        }
        
        if (!currentConversationId) {
            throw new Error('Failed to create or retrieve a valid conversation ID.');
        }

        const userMessageToSave = {
            conversation_id: currentConversationId,
            company_id: companyId,
            role: 'user' as const,
            content: content,
        };
        await saveMessage(userMessageToSave);

        const cookieStore = cookies();
        const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
        const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

        if (!supabaseUrl || !supabaseAnonKey) {
            throw new Error("Supabase environment variables are not set.");
        }
        
        const supabase = createServerClient(
            supabaseUrl,
            supabaseAnonKey,
            {
              cookies: { get: (name: string) => cookieStore.get(name)?.value },
            }
        );
        const { data: historyData, error: historyError } = await supabase
            .from('messages')
            .select('*')
            .eq('conversation_id', currentConversationId)
            .order('created_at', { ascending: false })
            .limit(config.ai.historyLimit);

        if (historyError) {
            logError(historyError, { context: 'Failed to fetch conversation history' });
        }
        const conversationHistory = (historyData || []).map(m => ({
            role: m.role as 'user' | 'assistant' | 'tool',
            content: [{ text: m.content }]
        })).reverse();


        const response = await universalChatFlow({ companyId, conversationHistory });
        
        const finalConversationId = (response as any).conversationId || currentConversationId;
        if (!finalConversationId) {
            throw new Error('Could not determine conversation ID after processing message.');
        }

        const newMessage: Message = {
            id: `ai_${Date.now()}`,
            conversation_id: finalConversationId,
            company_id: companyId,
            role: 'assistant',
            content: response.response,
            visualization: response.visualization,
            confidence: response.confidence,
            assumptions: response.assumptions,
            component: (response as any).component,
            componentProps: (response as any).componentProps,
            isError: (response as { isError?: boolean }).isError || false,
            created_at: new Date().toISOString(),
        };

        const { id, created_at, ...messageToSave } = newMessage;
        await saveMessage(messageToSave);
        
        return { newMessage, conversationId: finalConversationId };

    } catch(e) {
        logError(e, { context: `handleUserMessage action for conversation ${conversationId}` });
        return { error: `Sorry, I encountered an unexpected problem: ${getErrorMessage(e)}` };
    }
}
