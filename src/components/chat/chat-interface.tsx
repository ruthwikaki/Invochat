
'use client';

import { handleUserMessage } from '@/app/actions';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ScrollArea } from '@/components/ui/scroll-area';
import type { Message } from '@/types';
import { ArrowRight } from 'lucide-react';
import { useEffect, useRef, useState, useTransition } from 'react';
import { ChatMessage } from './chat-message';
import { useToast } from '@/hooks/use-toast';
import { APP_CONFIG } from '@/config/app-config';

const quickActions = APP_CONFIG.chat.quickActions;

type ChatInterfaceProps = {
    messages: Message[];
    setMessages: React.Dispatch<React.SetStateAction<Message[]>>;
}

export function ChatInterface({ messages, setMessages }: ChatInterfaceProps) {
  const [input, setInput] = useState('');
  const [isPending, startTransition] = useTransition();
  const scrollAreaRef = useRef<HTMLDivElement>(null);
  const { toast } = useToast();

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setInput(e.target.value);
  };

  const processAndSetMessages = (userMessageText: string) => {
    const userMessage: Message = {
      id: Date.now().toString(),
      role: 'user',
      content: userMessageText,
      timestamp: Date.now(),
    };
    
    setMessages(prev => [...prev, userMessage]);
    
    startTransition(async () => {
      // Add loading message
      const loadingMessage: Message = {
        id: 'loading',
        role: 'assistant',
        content: '...',
        timestamp: Date.now(),
      };
      setMessages(prev => [...prev, loadingMessage]);
      
      try {
        const response = await handleUserMessage({
          // Pass the history *with* the new user message
          conversationHistory: [...messages, userMessage].slice(-APP_CONFIG.ai.historyLimit),
        });
        
        // Replace loading message with actual response
        setMessages(prev => {
          const filtered = prev.filter(m => m.id !== 'loading');
          return [...filtered, response];
        });
      } catch (error: any) {
        toast({
          variant: 'destructive',
          title: 'Error',
          description: error.message || 'Could not get response from InvoChat.',
        });
        // Remove loading message on error
        setMessages(prev => prev.filter(m => m.id !== 'loading'));
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
    processAndSetMessages(action);
    setInput('');
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        if (input.trim() && !isPending) {
            processAndSetMessages(input);
            setInput('');
        }
    }
  };


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
    <div className="flex h-full flex-grow flex-col justify-between bg-background">
      <ScrollArea className="flex-grow" ref={scrollAreaRef}>
        <div className="mx-auto max-w-4xl space-y-6 p-4">
          {messages.map((m) => (
             m.id === 'loading' ? (
                <ChatMessage key={m.id} message={m} isLoading />
             ) : (
                <ChatMessage key={m.id} message={m} />
             )
          ))}
        </div>
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
            onChange={handleInputChange}
            onKeyDown={handleKeyDown}
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
