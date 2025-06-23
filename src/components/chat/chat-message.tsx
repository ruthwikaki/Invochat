'use client';

import { InvoChatLogo } from '@/components/invochat-logo';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { cn } from '@/lib/utils';
import type { Message } from '@/types';
import type { User as FirebaseUser } from 'firebase/auth';

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
  user,
}: {
  message: Message;
  isLoading?: boolean;
  user: FirebaseUser | null;
}) {
  const isUserMessage = message.role === 'user';
  return (
    <div
      className={cn(
        'flex items-start gap-3',
        isUserMessage ? 'justify-end' : 'justify-start'
      )}
    >
      {!isUserMessage && (
        <Avatar className="h-8 w-8 shrink-0">
          <InvoChatLogo className="h-8 w-8" />
        </Avatar>
      )}
      <div
        className={cn(
          'relative max-w-xl rounded-2xl px-4 py-3 shadow-sm animate-in fade-in slide-in-from-bottom-2 duration-300',
          isUserMessage
            ? 'rounded-br-none bg-primary text-primary-foreground'
            : 'rounded-bl-none bg-card text-card-foreground'
        )}
      >
        <div className="text-base">
          {isLoading ? <TypingIndicator /> : message.content}
        </div>
      </div>
      {isUserMessage && (
        <Avatar className="h-8 w-8 shrink-0">
          <AvatarImage src={user?.photoURL ?? undefined} alt={user?.displayName ?? 'User'} data-ai-hint="user avatar"/>
          <AvatarFallback>{user?.email?.charAt(0).toUpperCase() ?? 'U'}</AvatarFallback>
        </Avatar>
      )}
    </div>
  );
}
