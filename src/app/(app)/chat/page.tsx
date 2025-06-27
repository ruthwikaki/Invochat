
import { getConversations, getMessages } from '@/app/actions';
import { ChatInterface } from '@/components/chat/chat-interface';
import { ConversationSidebar } from '@/components/chat/conversation-sidebar';
import { SidebarTrigger } from '@/components/ui/sidebar';
import type { Conversation, Message } from '@/types';
import { Bot } from 'lucide-react';

export const dynamic = 'force-dynamic';

function WelcomePanel() {
  return (
    <div className="flex h-full flex-col items-center justify-center text-center">
      <Bot className="h-20 w-20 text-muted-foreground" />
      <h2 className="mt-6 text-2xl font-semibold">Welcome to InvoChat</h2>
      <p className="mt-2 text-muted-foreground">
        Select a conversation from the sidebar or start a new one to begin.
      </p>
    </div>
  );
}

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
      <ConversationSidebar
        conversations={conversations}
        activeConversationId={conversationId}
      />
      <main className="flex-1 flex flex-col h-full">
        <div className="flex md:hidden items-center p-4 border-b shrink-0">
          <SidebarTrigger />
          <h1 className="text-xl font-semibold ml-2">Conversations</h1>
        </div>
        
        {conversationId ? (
          <ChatInterface
            key={conversationId} // Re-mount component when ID changes
            conversationId={conversationId}
            initialMessages={messages}
          />
        ) : (
          <WelcomePanel />
        )}
      </main>
    </div>
  );
}
