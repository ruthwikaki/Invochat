
'use client';

import { handleUserMessage } from '@/app/actions';
import { DeadStockTable } from '@/components/ai-response/dead-stock-table';
import { ReorderList } from '@/components/ai-response/reorder-list';
import { SupplierPerformanceTable } from '@/components/ai-response/supplier-performance-table';
import { DynamicChart } from '@/components/ai-response/dynamic-chart';
import { DataTable } from '@/components/ai-response/data-table';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ScrollArea } from '@/components/ui/scroll-area';
import type { AssistantMessagePayload, Message } from '@/types';
import { ArrowRight } from 'lucide-react';
import { useEffect, useRef, useState, useTransition } from 'react';
import { ChatMessage } from './chat-message';
import { useToast } from '@/hooks/use-toast';
import { APP_CONFIG } from '@/config/app-config';

const AiComponentMap = {
  DeadStockTable,
  SupplierPerformanceTable,
  ReorderList,
  DynamicChart,
  DataTable,
};

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

  const processResponse = (response: AssistantMessagePayload) => {
    let contentNode: React.ReactNode = response.content;

    if (response.component && response.component in AiComponentMap) {
      const Component = AiComponentMap[response.component as keyof typeof AiComponentMap];
      contentNode = (
        <div className="space-y-2">
          {response.content && <p>{response.content}</p>}
          <Component {...response.props} />
        </div>
      );
    }
    setMessages((prev) => [
      ...prev,
      {
        id: response.id,
        role: 'assistant',
        content: contentNode,
        timestamp: Date.now(),
      },
    ]);
  };

  const submitMessage = (messageText: string) => {
    if (!messageText.trim()) return;

    const userMessage: Message = {
      id: Date.now().toString(),
      role: 'user',
      content: messageText,
      timestamp: Date.now(),
    };
    setMessages((prev) => [...prev, userMessage]);

    // Create conversation history for context, including the new user message
    const conversationHistory = [...messages, userMessage]
      .filter(m => m.role !== 'system')
      .slice(-APP_CONFIG.ai.historyLimit) // Last X messages for context
      .map(m => ({
        role: m.role as 'user' | 'assistant',
        content: typeof m.content === 'string' ? m.content : 'Visual response'
      }));

    startTransition(async () => {
      try {
        const response = await handleUserMessage({ 
          message: messageText,
          conversationHistory 
        });
        processResponse(response);
      } catch (e) {
        toast({ 
          variant: 'destructive', 
          title: 'Error', 
          description: 'Could not get response from InvoChat.'
        });
      }
    });
  };

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    submitMessage(input);
    setInput('');
  };

  const handleQuickAction = (action: string) => {
    submitMessage(action);
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        if (input.trim() && !isPending) {
            submitMessage(input);
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
  }, [messages]);

  return (
    <div className="flex h-full flex-grow flex-col justify-between bg-background">
      <ScrollArea className="flex-grow" ref={scrollAreaRef}>
        <div className="mx-auto max-w-4xl space-y-6 p-4">
          {messages.map((m) => (
            <ChatMessage key={m.id} message={m} />
          ))}
          {isPending && (
            <ChatMessage
              message={{
                id: 'loading',
                role: 'assistant',
                content: '...',
                timestamp: Date.now(),
              }}
              isLoading
            />
          )}
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
