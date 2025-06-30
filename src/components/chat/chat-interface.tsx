
'use client';

import { handleUserMessage } from '@/app/actions';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ScrollArea } from '@/components/ui/scroll-area';
import type { Message } from '@/types';
import { ArrowRight, Bot, Mic, BarChart2, Package, Truck, Sparkles } from 'lucide-react';
import { useEffect, useRef, useState, useTransition } from 'react';
import { ChatMessage } from './chat-message';
import { useToast } from '@/hooks/use-toast';
import { config } from '@/config/app-config';
import { useRouter } from 'next/navigation';
import { Card, CardContent } from '@/components/ui/card';
import { getErrorMessage } from '@/lib/error-handler';
import { motion } from 'framer-motion';

const quickActions = config.chat.quickActions;

function ChatWelcomePanel({ onQuickActionClick }: { onQuickActionClick: (action: string) => void }) {
    const iconMap: { [key: string]: React.ElementType } = {
        'top 5 products': BarChart2,
        'inventory value': Package,
        'suppliers': Truck,
        'forecast': Sparkles,
    }
    const getIcon = (text: string) => {
        for (const key in iconMap) {
            if (text.toLowerCase().includes(key)) {
                return iconMap[key];
            }
        }
        return Bot;
    }

    return (
      <div className="flex h-full flex-col items-center justify-center text-center p-4">
        <motion.div
            initial={{ scale: 0, opacity: 0 }}
            animate={{ 
                scale: 1, 
                opacity: 1,
                rotate: [0, -5, 5, -5, 5, 0],
            }}
            transition={{
                scale: { type: 'spring', stiffness: 260, damping: 20, delay: 0.2 },
                opacity: { duration: 0.3, delay: 0.2 },
                rotate: { repeat: Infinity, duration: 3, ease: 'easeInOut', delay: 1 }
            }}
            className="flex flex-col items-center justify-center p-8 rounded-full bg-card shadow-xl"
        >
            <Bot className="h-16 w-16 text-primary" />
        </motion.div>
        <motion.h2
            initial={{ y: 20, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ duration: 0.5, delay: 0.4 }}
            className="mt-6 text-2xl font-semibold"
        >
            Welcome to InvoChat
        </motion.h2>
        <motion.p
            initial={{ y: 20, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ duration: 0.5, delay: 0.5 }}
            className="mt-2 max-w-md text-muted-foreground"
        >
          Ask me anything about your inventory, sales, or suppliers. Or, try one of these quick starts:
        </motion.p>
        <motion.div
            initial={{ y: 20, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ duration: 0.5, delay: 0.6 }}
            className="mt-6 grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-2xl w-full"
        >
            {quickActions.map((action, i) => {
                const Icon = getIcon(action);
                return (
                    <Card key={i} className="text-left bg-card/50 hover:bg-muted/80 backdrop-blur-sm transition-all duration-300 hover:shadow-lg hover:-translate-y-1 cursor-pointer" onClick={() => onQuickActionClick(action)}>
                        <CardContent className="p-4 flex items-center gap-4">
                            <Icon className="h-6 w-6 text-primary" />
                            <p className="font-medium text-sm">{action}</p>
                        </CardContent>
                    </Card>
                )
            })}
        </motion.div>
      </div>
    );
}

export function ChatInterface({ conversationId, initialMessages }: { conversationId?: string; initialMessages: Message[] }) {
  const [input, setInput] = useState('');
  const [messages, setMessages] = useState<Message[]>(initialMessages);
  const [isPending, startTransition] = useTransition();
  const scrollAreaRef = useRef<HTMLDivElement>(null);
  const router = useRouter();
  const { toast } = useToast();

  const isNewChat = !conversationId;

  const processAndSetMessages = async (userMessageText: string) => {
    // Placeholder until auth is restored
    const companyId = 'default-company-id';

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
            setMessages(prev => prev.filter(m => m.id !== 'loading').map(m => m.id === tempId ? optimisticUserMessage : m).concat(errorMessage));

        } else if (response.conversationId && isNewChat) {
            router.push(`/chat?id=${response.conversationId}`);
        } else if (response.newMessage) {
            // Replace the loading message with the real one
            setMessages(prev => prev.filter(m => m.id !== 'loading').map(m => m.id === tempId ? optimisticUserMessage : m).concat(response.newMessage!));
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
        setMessages(prev => prev.filter(m => m.id !== 'loading').map(m => m.id === tempId ? optimisticUserMessage : m).concat(errorMessage));
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
    <div className="flex h-full flex-grow flex-col justify-between bg-card/30">
      <ScrollArea className="flex-grow" ref={scrollAreaRef}>
        <div className="absolute inset-0 -z-10 h-full w-full bg-background bg-[radial-gradient(#e5e7eb_1px,transparent_1px)] [background-size:16px_16px] [mask-image:radial-gradient(ellipse_50%_50%_at_50%_50%,#000_70%,transparent_100%)] opacity-5 dark:opacity-10"></div>
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
      <div className="mx-auto w-full max-w-4xl p-4 border-t bg-background/80 backdrop-blur-md">
        {messages.length > 0 && (
            <div className="mb-3 overflow-x-auto pb-2">
                <div className="flex gap-2 w-max">
                    {quickActions.slice(0, 3).map((action, i) => (
                        <Button key={i} variant="outline" size="sm" className="rounded-full" onClick={() => handleQuickAction(action)}>
                            {action}
                        </Button>
                    ))}
                </div>
            </div>
        )}
        <form onSubmit={handleSubmit} className="relative flex items-center gap-2">
          <Input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Ask anything about your inventory..."
            className="h-12 flex-1 rounded-full pr-24 text-base"
            disabled={isPending}
          />
          <div className="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1">
            <Button
                type="button"
                variant="ghost"
                size="icon"
                className="rounded-full"
                disabled={isPending}
                aria-label="Voice input"
            >
                <Mic className="h-5 w-5" />
            </Button>
            <Button
                type="submit"
                size="icon"
                className="rounded-full bg-gradient-to-br from-primary to-violet-500 text-white shadow-lg hover:scale-105 transition-transform"
                disabled={isPending || !input.trim()}
            >
                <ArrowRight className="h-5 w-5" />
                <span className="sr-only">Send</span>
            </Button>
          </div>
        </form>
      </div>
    </div>
  );
}
