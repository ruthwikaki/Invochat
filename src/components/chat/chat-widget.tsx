'use client';

import { Button } from '@/components/ui/button';
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetClose } from '@/components/ui/sheet';
import { MessageSquare, Trash2, X } from 'lucide-react';
import { useState, useEffect } from 'react';
import { ChatInterface } from './chat-interface';
import { cn } from '@/lib/utils';
import type { Message } from '@/types';

const getInitialMessages = (): Message[] => [
  {
    id: 'init',
    role: 'assistant',
    content: "Hello! I'm InvoChat, your inventory assistant.",
    timestamp: Date.now(),
  },
];

export function ChatWidget() {
  const [isOpen, setIsOpen] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);

  useEffect(() => {
    if (isOpen && messages.length === 0) {
      setMessages(getInitialMessages());
    }
  }, [isOpen, messages.length]);

  const clearChat = () => {
    setMessages(getInitialMessages());
  };

  return (
    <>
      <div className="fixed bottom-6 right-6 z-50">
        <Button
          size="icon"
          className="h-14 w-14 rounded-full shadow-lg"
          onClick={() => setIsOpen(!isOpen)}
        >
          {isOpen ? <X className="h-6 w-6" /> : <MessageSquare className="h-6 w-6" />}
          <span className="sr-only">Toggle Chat</span>
        </Button>
      </div>

      <Sheet open={isOpen} onOpenChange={setIsOpen}>
        <SheetContent
          side="right"
          className={cn(
            'flex h-full flex-col p-0 w-full sm:max-w-md'
          )}
        >
          <SheetHeader className="p-4 border-b flex-row justify-between items-center">
            <SheetTitle>InvoChat Assistant</SheetTitle>
            <div className="flex items-center gap-2">
                <Button variant="ghost" size="icon" onClick={clearChat} disabled={messages.length === 0}>
                    <Trash2 className="h-4 w-4" />
                    <span className="sr-only">Clear Chat</span>
                </Button>
                <SheetClose asChild>
                     <Button variant="ghost" size="icon" className="md:hidden">
                        <X className="h-4 w-4" />
                        <span className="sr-only">Close</span>
                    </Button>
                </SheetClose>
            </div>
          </SheetHeader>
          <ChatInterface messages={messages} setMessages={setMessages} />
        </SheetContent>
      </Sheet>
    </>
  );
}
