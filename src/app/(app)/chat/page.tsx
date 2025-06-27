
import { getConversations, getMessages } from '@/app/actions';
import { ChatInterface } from '@/components/chat/chat-interface';
import { ConversationSidebar } from '@/components/chat/conversation-sidebar';
import { SidebarTrigger } from '@/components/ui/sidebar';
import type { Conversation, Message } from '@/types';

export const dynamic = 'force-dynamic';

export default async function ChatPage({
  searchParams,
}: {
  searchParams?: { id?: string };
}) {
  const conversationId = searchParams?.id;
  const conversations: Conversation[] = await getConversations();
  const messages: Message[] = conversationId ? await getMessages(conversationId) : [];

  return (
    <div className="flex h-full">
      {/* This component now contains the responsive Sidebar that works on mobile */}
      <ConversationSidebar
        conversations={conversations}
        activeConversationId={conversationId}
      />
      <main className="flex-1 flex flex-col h-full">
        {/* The mobile header with a now-functional trigger */}
        <div className="flex md:hidden items-center p-4 border-b shrink-0">
          <SidebarTrigger />
          <h1 className="text-xl font-semibold ml-2">Conversations</h1>
        </div>
        
        <ChatInterface
          key={conversationId} // Re-mount component when ID changes
          conversationId={conversationId}
          initialMessages={messages}
        />
      </main>
    </div>
  );
}
