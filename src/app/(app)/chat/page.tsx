'use client';

import { ChatInterface } from '@/components/chat/chat-interface';
import { Button } from '@/components/ui/button';
import { SidebarTrigger } from '@/components/ui/sidebar';
import type { Message } from '@/types';
import { Trash2 } from 'lucide-react';
import { useState, useEffect } from 'react';

const getInitialMessages = (): Message[] => [
  {
    id: 'init',
    role: 'assistant',
    content: "Hello! I'm ARVO, your inventory assistant.",
    timestamp: Date.now(),
  },
];

export default function ChatPage() {
  const [messages, setMessages] = useState<Message[]>([]);

  useEffect(() => {
    // Initialize messages on the client to avoid hydration mismatch
    setMessages(getInitialMessages());
  }, []);
  
  const clearChat = () => {
    setMessages(getInitialMessages());
  };

  return (
    <div className="flex flex-col h-full animate-fade-in">
        <div className="flex items-center justify-between p-4 border-b shrink-0">
            <div className="flex items-center gap-2">
                <SidebarTrigger className="md:hidden" />
                <h1 className="text-2xl font-semibold">Chat with ARVO</h1>
            </div>
            <Button variant="ghost" size="icon" onClick={clearChat} disabled={messages.length <= 1}>
                <Trash2 className="h-4 w-4" />
                <span className="sr-only">Clear Chat</span>
            </Button>
        </div>
        <ChatInterface
            messages={messages}
            setMessages={setMessages}
        />
    </div>
  );
}
