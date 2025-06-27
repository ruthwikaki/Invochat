
'use client';

import { handleUserMessage } from '@/app/actions';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ScrollArea } from '@/components/ui/scroll-area';
import type { Message } from '@/types';
import { ArrowRight, Bot } from 'lucide-react';
import { useEffect, useRef, useState, useTransition } from 'react';
import { ChatMessage } from './chat-message';
import { useToast } from '@/hooks/use-toast';
import { APP_CONFIG } from '@/config/app-config';
import { useRouter } from 'next/navigation';

const quickActions = APP_CONFIG.chat.quickActions;

type ChatInterfaceProps = {
    conversationId?: string;
    initialMessages: Message[];
}

function ChatWelcomePanel() {
    return (
      <div className="flex h-full flex-col items-center justify-center text-center p-4">
        <Bot className="h-20 w-20 text-muted-foreground" />
        <h2 className="mt-6 text-2xl font-semibold">Start a new conversation</h2>
        <p className="mt-2 text-muted-foreground">
          Ask me anything about your inventory, sales, or suppliers.
        </p>
      </div>
    );
}

export function ChatInterface({ conversationId, initialMessages }: ChatInterfaceProps) {
  const [input, setInput] = useState('');
  const [messages, setMessages] = useState<Message[]>(initialMessages);
  const [isPending, startTransition] = useTransition();
  const scrollAreaRef = useRef<HTMLDivElement>(null);
  const router = useRouter();
  const { toast } = useToast();

  const isNewChat = !conversationId;

  const processAndSetMessages = (userMessageText: string) => {
    const tempId = `temp_${Date.now()}`;
    const optimisticUserMessage: Message = {
      id: tempId,
      role: 'user',
      content: userMessageText,
      created_at: new Date().toISOString(),
      conversation_id: conversationId || tempId,
    };
    
    setMessages(prev => [...prev, optimisticUserMessage]);
    
    const loadingMessage: Message = {
      id: 'loading',
      role: 'assistant',
      content: '...',
      created_at: new Date().toISOString(),
      conversation_id: conversationId || tempId,
    };
    setMessages(prev => [...prev, loadingMessage]);

    startTransition(async () => {
      try {
        const response = await handleUserMessage({
          content: userMessageText,
          conversationId: conversationId || null,
        });

        if (response.error) {
            toast({ variant: 'destructive', title: 'Error', description: response.error });
            setMessages(prev => prev.filter(m => m.id !== tempId && m.id !== 'loading'));
        } else if (response.conversationId && isNewChat) {
            // New conversation created, redirect to its URL
            router.push(`/chat?id=${response.conversationId}`);
        } else {
            // Existing conversation, just refresh data
            router.refresh();
        }

      } catch (error: any) {
        toast({
          variant: 'destructive',
          title: 'Error',
          description: error.message || 'Could not get response from InvoChat.',
        });
        setMessages(prev => prev.filter(m => m.id !== tempId && m.id !== 'loading'));
      }
    });
  };

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (input.trim() && !isPending) {
      processAndSetMessages(input);
      setInput('');
    }
  };

  const handleQuickAction = (action: string) => {
    setInput('');
    processAndSetMessages(action);
  };
  
  useEffect(() => {
    setMessages(initialMessages);
  }, [initialMessages]);

  useEffect(() => {
    if (scrollAreaRef.current) {
      const viewport = scrollAreaRef.current.querySelector('div');
      if (viewport) {
        viewport.scrollTo({
            top: viewport.scrollHeight,
            behavior: 'smooth',
        });
      }
    }
  }, [messages, isPending]);

  return (
    <div className="flex h-full flex-grow flex-col justify-between bg-muted/30">
      <ScrollArea className="flex-grow" ref={scrollAreaRef}>
        {messages.length > 0 ? (
            <div className="mx-auto w-full max-w-4xl space-y-6 p-4">
                {messages.map((m) => (
                    <ChatMessage 
                        key={m.id} 
                        message={m} 
                        isLoading={m.id === 'loading'} 
                    />
                ))}
            </div>
        ) : (
            <ChatWelcomePanel />
        )}
      </ScrollArea>
      <div className="mx-auto w-full max-w-4xl p-4 border-t bg-background">
        <div className="mb-2 flex flex-wrap gap-2">
          {quickActions.map((action) => (
            <Button
              key={action}
              variant="outline"
              size="sm"
              className="rounded-full h-auto py-1 px-3 text-xs"
              onClick={() => handleQuickAction(action)}
              disabled={isPending}
            >
              {action}
            </Button>
          ))}
        </div>
        <form onSubmit={handleSubmit} className="relative flex items-center">
          <Input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Ask anything about your inventory..."
            className="h-12 flex-1 rounded-full pr-14 text-base"
            disabled={isPending}
          />
          <Button
            type="submit"
            size="icon"
            className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full"
            disabled={isPending || !input.trim()}
          >
            <ArrowRight className="h-5 w-5" />
            <span className="sr-only">Send</span>
          </Button>
        </form>
      </div>
    </div>
  );
}
