
import { getMessages } from '@/app/actions';
import { ChatInterface } from '@/components/chat/chat-interface';
import type { Message } from '@/types';

export const dynamic = 'force-dynamic';

export default async function ChatPage({
  searchParams,
}: {
  searchParams?: { id?: string; q?: string };
}) {
  const conversationId = searchParams?.id;
  const prefillQuery = searchParams?.q;
  
  // Message fetching remains here as it's specific to the conversation being viewed.
  const messages: Message[] = conversationId ? await getMessages(conversationId) : [];

  return (
    <div className="flex h-full -m-4 md:-m-6 lg:-m-8">
      {/* The main layout now provides the unified sidebar for all pages. */}
      <main className="flex-1 flex flex-col h-full">
        <ChatInterface
          key={conversationId} // Re-mount component when ID changes
          conversationId={conversationId}
          initialMessages={messages}
          prefillQuery={prefillQuery}
        />
      </main>
    </div>
  );
}
