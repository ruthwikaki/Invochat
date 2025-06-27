
'use client';

import { InvochatLogo } from '@/components/invochat-logo';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { cn } from '@/lib/utils';
import type { Message } from '@/types';
import { useAuth } from '@/context/auth-context';
import { DataVisualization } from './data-visualization';

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
  const { user } = useAuth();
  const isUserMessage = message.role === 'user';
  
  const getInitials = (email: string | undefined) => {
    if (!email) return 'U';
    return email.charAt(0).toUpperCase();
  };

  return (
    <div className={cn("flex flex-col gap-2", isUserMessage && "items-end")}>
      <div className={cn("flex items-start gap-3 w-full", isUserMessage ? "justify-end" : "justify-start")}>
        {!isUserMessage && (
          <InvochatLogo className="h-8 w-8 shrink-0 text-primary" />
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
            <AvatarFallback>{getInitials(user?.email)}</AvatarFallback>
          </Avatar>
        )}
      </div>
      
      {/* Render visualization if present, aligned correctly under the message bubble */}
      {message.visualization && (
        <div className={cn("max-w-xl w-full animate-in fade-in slide-in-from-bottom-2 duration-300", !isUserMessage && "ml-11")}>
          <DataVisualization
            visualization={message.visualization}
            title={message.visualization.config?.title}
          />
        </div>
      )}
    </div>
  );
}
