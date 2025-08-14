
import { NextResponse } from 'next/server';
import { handleUserMessage } from '@/app/data-actions';
import { getErrorMessage, logError } from '@/lib/error-handler';
import * as Sentry from '@sentry/nextjs';
import { rateLimit } from '@/lib/redis';
import { config } from '@/config/app-config';
import type { NextRequest } from 'next/server';
import { headers } from 'next/headers';


export async function POST(req: NextRequest) {
    if (process.env.MOCK_AI === 'true') {
        return NextResponse.json({
            newMessage: {
                id: `mock_${Date.now()}`,
                role: 'assistant',
                content: 'This is a mocked AI response for testing.',
                created_at: new Date().toISOString(),
                isError: false,
            },
            conversationId: 'mock-conversation-id',
        });
    }

    try {
        const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
        const { limited } = await rateLimit(ip, 'ai-chat', config.ratelimit.ai, 3600);
        if (limited) {
            return NextResponse.json({ error: 'You have made too many requests. Please try again in an hour.' }, { status: 429 });
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
