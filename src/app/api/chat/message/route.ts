
import { NextResponse } from 'next/server';
import { handleUserMessage } from '@/app/data-actions';
import { getErrorMessage } from '@/lib/error-handler';

export async function POST(req: Request) {
    try {
        if (process.env.NODE_ENV === 'test' || process.env.MOCK_AI === 'true') {
            const { message, conversationId } = await req.json();
            const newMessage = {
              id: crypto.randomUUID(),
              role: 'assistant',
              content: `Okay! You said: ${message}`,
            };
            return NextResponse.json({
              newMessage,
              conversationId: conversationId ?? crypto.randomUUID(),
            });
        }

        const body = await req.json();
        const result = await handleUserMessage(body);

        if (result.error) {
            return NextResponse.json({ error: result.error }, { status: 500 });
        }

        return NextResponse.json(result);
    } catch(e) {
        const errorMessage = getErrorMessage(e);
        return NextResponse.json({ error: errorMessage }, { status: 500 });
    }
}
