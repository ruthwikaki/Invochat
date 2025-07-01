
'use client';

import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { cn } from '@/lib/utils';
import type { Message } from '@/types';
import { DataVisualization } from './data-visualization';
import { BrainCircuit, AlertTriangle, Bot } from 'lucide-react';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip"
import DOMPurify from 'isomorphic-dompurify';
import { motion } from 'framer-motion';
import { DeadStockTable } from '@/components/ai-response/dead-stock-table';
import { ReorderList } from '@/components/ai-response/reorder-list';
import { SupplierPerformanceTable } from '@/components/ai-response/supplier-performance-table';
import React from 'react';

// New futuristic loading indicator
function LoadingIndicator() {
    return (
        <div className="flex items-center space-x-2">
            <motion.div
                className="h-2 w-2 bg-primary/80 rounded-full"
                animate={{
                    y: [0, -4, 0],
                    transition: { duration: 1, repeat: Infinity, ease: "easeInOut" }
                }}
            />
            <motion.div
                className="h-2 w-2 bg-primary/80 rounded-full"
                animate={{
                    y: [0, -4, 0],
                    transition: { duration: 1, repeat: Infinity, ease: "easeInOut", delay: 0.2 }
                }}
            />
            <motion.div
                className="h-2 w-2 bg-primary/80 rounded-full"
                animate={{
                    y: [0, -4, 0],
                    transition: { duration: 1, repeat: Infinity, ease: "easeInOut", delay: 0.4 }
                }}
            />
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

// Animated Bot Avatar
function BotAvatar({ isError }: { isError?: boolean }) {
    return (
        <motion.div
            initial={{ scale: 0, rotate: -180 }}
            animate={{ scale: 1, rotate: 0 }}
            transition={{ duration: 0.5, type: 'spring', stiffness: 150 }}
            className={cn(
                'h-9 w-9 shrink-0 rounded-full bg-gradient-to-br from-primary via-violet-500 to-purple-600 flex items-center justify-center shadow-lg',
                isError && 'from-destructive/80 to-rose-500/80'
            )}
        >
            <Avatar className={cn('h-8 w-8 bg-card')}>
                <AvatarFallback className={cn('bg-transparent', isError && 'text-destructive')}>
                   {isError ? <AlertTriangle className="h-5 w-5" /> : <Bot className="h-5 w-5" />}
                </AvatarFallback>
            </Avatar>
        </motion.div>
    );
}

// Map component names to actual components
const componentMap: { [key: string]: React.ElementType } = {
    deadStockTable: DeadStockTable,
    reorderList: ReorderList,
    supplierPerformanceTable: SupplierPerformanceTable,
};

export function ChatMessage({
  message,
}: {
  message: Message;
}) {
  const isUserMessage = message.role === 'user';
  const isLoading = message.id === 'loading';
  
  const getInitials = (email: string | undefined) => {
    if (!email) return 'U';
    return email.charAt(0).toUpperCase();
  };
  
  const sanitizedContent = !isLoading ? DOMPurify.sanitize(message.content, {
    ALLOWED_TAGS: ['b', 'i', 'em', 'strong', 'a', 'br', 'p'],
    ALLOWED_ATTR: ['href']
  }) : '';

  const messageVariants = {
      hidden: { opacity: 0, y: 20 },
      visible: { opacity: 1, y: 0, transition: { duration: 0.4, ease: 'easeOut' } }
  };

  const CustomComponent = message.component ? componentMap[message.component] : null;

  return (
    <motion.div
        variants={messageVariants}
        initial="hidden"
        animate="visible"
        className={cn("flex flex-col gap-3", isUserMessage && "items-end")}
    >
      <div className={cn("flex items-start gap-3 w-full", isUserMessage ? "justify-end" : "justify-start")}>
        {!isUserMessage && <BotAvatar isError={message.isError} />}
        
        <div className={cn(
            'relative max-w-xl rounded-2xl px-4 py-3 shadow-lg space-y-2',
            isUserMessage
                ? 'rounded-br-none bg-primary text-primary-foreground'
                : 'rounded-bl-none bg-card text-card-foreground',
            message.isError && 'bg-destructive/10 border border-destructive/20 text-destructive'
        )}>
            <div
            className="text-base whitespace-pre-wrap selection:bg-primary/50"
            dangerouslySetInnerHTML={!isLoading ? { __html: sanitizedContent } : undefined}
            >
            {isLoading ? <LoadingIndicator /> : null}
            </div>
            {!isUserMessage && !isLoading && !message.isError &&(
            <ConfidenceDisplay confidence={message.confidence} assumptions={message.assumptions} />
            )}
        </div>

        {isUserMessage && (
          <Avatar className="h-9 w-9 shrink-0">
            <AvatarFallback>U</AvatarFallback>
          </Avatar>
        )}
      </div>
      
      {CustomComponent && (
          <div className={cn("max-w-xl w-full", !isUserMessage && "ml-12")}>
            <CustomComponent {...message.componentProps} />
          </div>
      )}

      {message.visualization && !CustomComponent && (
        <div className={cn("max-w-xl w-full", !isUserMessage && "ml-12")}>
          <DataVisualization
            visualization={message.visualization}
            title={message.visualization.config?.title}
          />
        </div>
      )}
    </motion.div>
  );
}
