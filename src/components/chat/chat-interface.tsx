
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
import { config } from '@/config/app-config';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/auth-context';
import { Card, CardContent } from '@/components/ui/card';
import { getErrorMessage } from '@/lib/error-handler';

const quickActions = config.chat.quickActions;

type ChatInterfaceProps = {
    conversationId?: string;
    initialMessages: Message[];
}

function ChatWelcomePanel({ onQuickActionClick }: { onQuickActionClick: (action: string) => void }) {
    return (
      <div className="flex h-full flex-col items-center justify-center text-center p-4">
        <div className="flex flex-col items-center justify-center p-8 rounded-full bg-card">
            <Bot className="h-16 w-16 text-primary" />
        </div>
        <h2 className="mt-6 text-2xl font-semibold">Start a new conversation</h2>
        <p className="mt-2 max-w-md text-muted-foreground">
          Ask me anything about your inventory, sales, or suppliers. Or, try one of these quick starts:
        </p>
        <div className="mt-6 grid grid-cols-1 sm:grid-cols-2 gap-3 max-w-lg w-full">
            {quickActions.map((action, i) => (
                <Card key={i} className="text-left hover:bg-muted transition-colors cursor-pointer" onClick={() => onQuickActionClick(action)}>
                    <CardContent className="p-4">
                        <p className="font-medium text-sm">{action}</p>
                    </CardContent>
                </Card>
            ))}
        </div>
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
  const { user } = useAuth();

  const isNewChat = !conversationId;

  const processAndSetMessages = async (userMessageText: string) => {
    const companyId = user?.app_metadata?.company_id;
    if (!companyId) {
        toast({
            variant: 'destructive',
            title: 'Authentication Error',
            description: 'Could not identify your company. Please try logging in again.',
        });
        return;
    }

    setInput('');

    const tempId = `temp_${Date.now()}`;
    const optimisticUserMessage: Message = {
      id: tempId,
      role: 'user',
      content: userMessageText,
      created_at: new Date().toISOString(),
      conversation_id: conversationId || tempId,
      company_id: companyId,
    };
    
    const tempLoadingMessage: Message = {
      id: 'loading',
      role: 'assistant',
      content: '...',
      created_at: new Date().toISOString(),
      conversation_id: conversationId || tempId,
      company_id: companyId,
    };

    setMessages(prev => [...prev, optimisticUserMessage, tempLoadingMessage]);

    startTransition(async () => {
      try {
        const response = await handleUserMessage({
          content: userMessageText,
          conversationId: conversationId || null,
        });

        if (response.error) {
            const errorMessage: Message = {
                id: `error_${Date.now()}`,
                role: 'assistant',
                content: response.error,
                created_at: new Date().toISOString(),
                conversation_id: conversationId || tempId,
                company_id: companyId,
                isError: true,
            };
            setMessages(prev => [...prev.filter(m => m.id !== 'loading'), errorMessage]);

        } else if (response.conversationId && isNewChat) {
            router.push(`/chat?id=${response.conversationId}`);
        } else if (response.newMessage) {
            // Replace the loading message with the real one
            setMessages(prev => [...prev.filter(m => m.id !== 'loading'), response.newMessage!]);
            router.refresh(); // Refresh server-side data like conversation list
        }

      } catch (error) {
        const errorMessage: Message = {
            id: `error_${Date.now()}`,
            role: 'assistant',
            content: getErrorMessage(error) || 'Could not get response from InvoChat.',
            created_at: new Date().toISOString(),
            conversation_id: conversationId || tempId,
            company_id: companyId,
            isError: true,
        };
        setMessages(prev => [...prev.filter(m => m.id !== 'loading'), errorMessage]);
      }
    });
  };

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (input.trim() && !isPending) {
      processAndSetMessages(input);
    }
  };

  const handleQuickAction = (action: string) => {
    if (!isPending) {
        processAndSetMessages(action);
    }
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
  }, [messages]);

  return (
    <div className="flex h-full flex-grow flex-col justify-between bg-card">
      <ScrollArea className="flex-grow" ref={scrollAreaRef}>
        {messages.length > 0 ? (
            <div className="mx-auto w-full max-w-4xl space-y-6 p-4">
                {messages.map((m) => (
                    <ChatMessage 
                        key={m.id} 
                        message={m}
                    />
                ))}
            </div>
        ) : (
            <ChatWelcomePanel onQuickActionClick={handleQuickAction} />
        )}
      </ScrollArea>
      <div className="mx-auto w-full max-w-4xl p-4 border-t bg-background">
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
