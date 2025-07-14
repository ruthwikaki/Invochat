
'use server';

import type { Message } from '@/types';
import { universalChatFlow } from '@/ai/flows/universal-chat';
import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import { logger } from '@/lib/logger';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { rateLimit } from '@/lib/redis';
import { config } from '@/config/app-config';
import { generateAnomalyExplanation } from '@/ai/flows/alert-explanation-flow';
import { getBusinessProfile } from '@/services/database';

async function getCompanyIdForChat(): Promise<string> {
    const cookieStore = cookies();
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: { get: (name: string) => cookieStore.get(name)?.value },
        }
    );
    const { data: { user } } = await supabase.auth.getUser();
    const companyId = user?.app_metadata?.company_id;
    if (!companyId) {
        throw new Error('Company ID not found for the current user.');
    }
    return companyId;
}

async function saveConversation(companyId: string, title: string) {
    const cookieStore = cookies();
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: { get: (name: string) => cookieStore.get(name)?.value },
        }
    );

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('User not authenticated.');
    
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
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
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
        const supabase = createServerClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL!,
            process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
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
        const supabase = createServerClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL!,
            process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
            {
            cookies: { get: (name: string) => cookieStore.get(name)?.value },
            }
        );
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) return [];

        // Update last accessed time
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


export async function handleUserMessage({ content, conversationId, source = 'chat_page' }: { content: string, conversationId: string | null, source?: string }) {
    try {
        const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
        const { limited } = await rateLimit(ip, 'ai_chat', config.ratelimit.ai, 60);
        if (limited) {
            return { error: 'You have reached the request limit. Please try again in a minute.' };
        }

        const companyId = await getCompanyIdForChat();
        
        let currentConversationId = conversationId;
        if (!currentConversationId) {
            const newTitle = content.length > 50 ? `${content.substring(0, 50)}...` : content;
            currentConversationId = await saveConversation(companyId, newTitle);
        }

        const userMessageToSave = {
            conversation_id: currentConversationId,
            company_id: companyId,
            role: 'user' as const,
            content: content,
        };
        await saveMessage(userMessageToSave);

        // Fetch recent messages for history
        const cookieStore = cookies();
        const supabase = createServerClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL!,
            process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
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
        
        let component = null;
        let componentProps = {};

        if (response.toolName === 'getDeadStockReport') {
            component = 'deadStockTable';
            componentProps = { data: response.data };
        }
        if (response.toolName === 'getReorderSuggestions') {
            component = 'reorderList';
            componentProps = { items: response.data };
        }
        if (response.toolName === 'getSupplierPerformanceReport') {
            component = 'supplierPerformanceTable';
            componentProps = { data: response.data };
        }
         if (response.toolName === 'createPurchaseOrdersFromSuggestions') {
            component = 'confirmation';
            componentProps = { ...response.data };
        }

        const newMessage: Message = {
            id: `ai_${Date.now()}`,
            conversation_id: currentConversationId,
            company_id: companyId,
            role: 'assistant',
            content: response.response,
            visualization: response.visualization,
            confidence: response.confidence,
            assumptions: response.assumptions,
            created_at: new Date().toISOString(),
            component,
            componentProps
        };

        await saveMessage({ ...newMessage, id: undefined, created_at: undefined });
        
        return { newMessage, conversationId: currentConversationId };

    } catch(e) {
        logError(e, { context: `handleUserMessage action for conversation ${conversationId}` });
        return { error: 'Sorry, I encountered an unexpected problem and could not respond. Please try again.' };
    }
}
