
import { NextResponse } from 'next/server';
import { handleUserMessage } from '@/app/data-actions';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import type { Message } from '@/types';
import * as Sentry from '@sentry/nextjs';

export async function POST(req: Request) {
    try {
        if (process.env.NODE_ENV === 'test' || process.env.MOCK_AI === 'true') {
            const cookieStore = cookies();
            const supabase = createServerClient(
                process.env.NEXT_PUBLIC_SUPABASE_URL!,
                process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
                {
                    cookies: {
                        get: (name) => cookieStore.get(name)?.value,
                    },
                }
            );
            const { data: { user } } = await supabase.auth.getUser();

            if (!user) {
                return NextResponse.json({ error: 'Unauthorized: Test user not authenticated.' }, { status: 401 });
            }
            
            const { content } = await req.json();
            const newMessage: Message = {
              id: crypto.randomUUID(),
              role: 'assistant',
              content: `This is a mocked AI response to: "${content}"`,
              created_at: new Date().toISOString(),
              conversation_id: crypto.randomUUID(),
              company_id: user.app_metadata.company_id,
            };
            return NextResponse.json({
              newMessage,
              conversationId: newMessage.conversation_id,
            });
        }

        const body = await req.json();
        const result = await handleUserMessage(body);

        if (result.error) {
            Sentry.captureMessage(`Chat API Error: ${result.error}`, 'error');
            return NextResponse.json({ error: result.error }, { status: 500 });
        }

        return NextResponse.json(result);
    } catch(e) {
        const errorMessage = getErrorMessage(e);
        logError(e, { context: 'POST /api/chat/message' });
        Sentry.captureException(e, { extra: { context: 'Chat API Exception' } });
        return NextResponse.json({ error: errorMessage }, { status: 500 });
    }
}
