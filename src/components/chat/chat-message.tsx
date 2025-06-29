
'use client';

import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { cn } from '@/lib/utils';
import type { Message } from '@/types';
import { useAuth } from '@/context/auth-context';
import { DataVisualization } from './data-visualization';
import { BrainCircuit, AlertTriangle, Bot } from 'lucide-react';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip"

function LoadingIndicator() {
    return (
        <div className="flex items-center space-x-2">
            <div className="flex items-center space-x-1">
                <span className="h-2 w-2 animate-pulse rounded-full bg-muted-foreground [animation-delay:-0.3s]" />
                <span className="h-2 w-2 animate-pulse rounded-full bg-muted-foreground [animation-delay:-0.15s]" />
                <span className="h-2 w-2 animate-pulse rounded-full bg-muted-foreground" />
            </div>
            <span className="text-sm italic text-muted-foreground">Thinking...</span>
        </div>
    );
}

function ConfidenceDisplay({ confidence, assumptions }: { confidence?: number | null, assumptions?: string[] | null }) {
    if (confidence === undefined || confidence === null) return null;

    const confidencePercentage = (confidence * 100).toFixed(0);
    let confidenceColor = 'text-success';
    if (confidence < 0.8) confidenceColor = 'text-warning';
    if (confidence < 0.5) confidenceColor = 'text-destructive';

    const tooltipText = assumptions && assumptions.length > 0 
        ? `Assumptions: ${assumptions.join(', ')}` 
        : 'No specific assumptions were made.';

    return (
        <TooltipProvider>
            <Tooltip delayDuration={100}>
                <TooltipTrigger asChild>
                    <div className="flex items-center gap-1 text-xs text-muted-foreground cursor-help">
                        <BrainCircuit className="h-3 w-3" />
                        <span className={cn('font-semibold', confidenceColor)}>{confidencePercentage}% confident</span>
                    </div>
                </TooltipTrigger>
                <TooltipContent className="max-w-xs">
                    <p>{tooltipText}</p>
                </TooltipContent>
            </Tooltip>
        </TooltipProvider>
    );
}

export function ChatMessage({
  message,
}: {
  message: Message;
}) {
  const { user } = useAuth();
  const isUserMessage = message.role === 'user';
  const isLoading = message.id === 'loading';
  
  const getInitials = (email: string | undefined) => {
    if (!email) return 'U';
    return email.charAt(0).toUpperCase();
  };

  return (
    <div className={cn("flex flex-col gap-2", isUserMessage && "items-end")}>
      <div className={cn("flex items-start gap-3 w-full", isUserMessage ? "justify-end" : "justify-start")}>
        {!isUserMessage && (
          <Avatar className={cn('h-8 w-8 shrink-0', message.isError && 'bg-destructive/20')}>
            <AvatarFallback className={cn('bg-transparent', message.isError && 'text-destructive')}>
               {message.isError ? <AlertTriangle className="h-5 w-5" /> : <Bot className="h-5 w-5" />}
            </AvatarFallback>
          </Avatar>
        )}
        <div
          className={cn(
            'relative max-w-xl rounded-2xl px-4 py-3 shadow-sm animate-in fade-in slide-in-from-bottom-2 duration-300 space-y-2',
            isUserMessage
              ? 'rounded-br-none bg-primary text-primary-foreground'
              : 'rounded-bl-none bg-card text-card-foreground',
            message.isError && 'bg-destructive/10 border border-destructive/20 text-destructive'
          )}
        >
          <div className="text-base whitespace-pre-wrap">
            {isLoading ? <LoadingIndicator /> : message.content}
          </div>
          {!isUserMessage && !isLoading && !message.isError &&(
            <ConfidenceDisplay confidence={message.confidence} assumptions={message.assumptions} />
          )}
        </div>
        {isUserMessage && (
          <Avatar className="h-8 w-8 shrink-0">
            <AvatarFallback>{getInitials(user?.email)}</AvatarFallback>
          </Avatar>
        )}
      </div>
      
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
