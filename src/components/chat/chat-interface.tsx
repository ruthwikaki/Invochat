'use client';

import { handleUserMessage } from '@/app/actions';
import { DeadStockTable } from '@/components/ai-response/dead-stock-table';
import { ReorderList } from '@/components/ai-response/reorder-list';
import { SupplierPerformanceTable } from '@/components/ai-response/supplier-performance-table';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ScrollArea } from '@/components/ui/scroll-area';
import type { AssistantMessagePayload, Message } from '@/types';
import { ArrowRight } from 'lucide-react';
import { useEffect, useRef, useState, useTransition } from 'react';
import { ChatMessage } from './chat-message';

const AiComponentMap = {
  DeadStockTable,
  SupplierPerformanceTable,
  ReorderList,
};

const initialMessages: Message[] = [
  {
    id: 'init',
    role: 'assistant',
    content: 'Hello! How can I help you with your inventory today?',
    timestamp: Date.now(),
  },
];

const quickActions = [
  'Show dead stock',
  'Which vendor delivers on time?',
  'What should I reorder from Johnson Supply?',
];

export function ChatInterface() {
  const [messages, setMessages] = useState<Message[]>(initialMessages);
  const [input, setInput] = useState('');
  const [isPending, startTransition] = useTransition();
  const scrollAreaRef = useRef<HTMLDivElement>(null);

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setInput(e.target.value);
  };

  const processResponse = (response: AssistantMessagePayload) => {
    let contentNode: React.ReactNode = response.content;

    if (response.component) {
      const Component = AiComponentMap[response.component];
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

    startTransition(async () => {
      const response = await handleUserMessage(messageText);
      processResponse(response);
    });
  };

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    submitMessage(input);
    setInput('');
  };

  const handleQuickAction = (action: string) => {
    setInput(action);
    submitMessage(action);
    setInput('');
  };

  useEffect(() => {
    if (scrollAreaRef.current) {
      scrollAreaRef.current.scrollTo({
        top: scrollAreaRef.current.scrollHeight,
        behavior: 'smooth',
      });
    }
  }, [messages]);

  return (
    <div className="flex h-full flex-grow flex-col justify-between p-4">
      <ScrollArea className="flex-grow" ref={scrollAreaRef}>
        <div className="mx-auto max-w-4xl space-y-6 px-4">
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
      <div className="mx-auto w-full max-w-4xl pt-4">
        <div className="mb-2 flex flex-wrap gap-2">
          {quickActions.map((action) => (
            <Button
              key={action}
              variant="outline"
              size="sm"
              className="rounded-full"
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
            placeholder="Ask ARVO about your inventory..."
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
