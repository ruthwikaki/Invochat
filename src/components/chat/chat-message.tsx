'use client';

import { ArvoLogo } from '@/components/arvo-logo';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { cn } from '@/lib/utils';
import type { Message } from '@/types';

function TypingIndicator() {
  return (
    <div className="flex items-center space-x-1">
      <span className="h-2 w-2 animate-pulse rounded-full bg-muted-foreground [animation-delay:-0.3s]" />
      <span className="h-2 w-2 animate-pulse rounded-full bg-muted-foreground [animation-delay:-0.15s]" />
      <span className="h-2 w-2 animate-pulse rounded-full bg-muted-foreground" />
    </div>
  );
}

export function ChatMessage({
  message,
  isLoading = false,
}: {
  message: Message;
  isLoading?: boolean;
}) {
  const isUser = message.role === 'user';
  return (
    <div
      className={cn(
        'flex items-start gap-3',
        isUser ? 'justify-end' : 'justify-start'
      )}
    >
      {!isUser && (
        <Avatar className="h-8 w-8 shrink-0">
          <ArvoLogo className="h-8 w-8" />
        </Avatar>
      )}
      <div
        className={cn(
          'relative max-w-xl rounded-2xl px-4 py-3 shadow-sm animate-in fade-in slide-in-from-bottom-2 duration-300',
          isUser
            ? 'rounded-br-none bg-primary text-primary-foreground'
            : 'rounded-bl-none bg-card text-card-foreground'
        )}
      >
        <div className="text-base">
          {isLoading ? <TypingIndicator /> : message.content}
        </div>
      </div>
      {isUser && (
        <Avatar className="h-8 w-8 shrink-0">
          <AvatarImage src="https://placehold.co/100x100.png" alt="User" data-ai-hint="user avatar"/>
          <AvatarFallback>U</AvatarFallback>
        </Avatar>
      )}
    </div>
  );
}
