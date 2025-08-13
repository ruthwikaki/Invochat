

'use client';

import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { cn } from '@/lib/utils';
import type { Message } from '@/types';
import { DataVisualization } from './data-visualization';
import { BrainCircuit, AlertTriangle, Bot, ThumbsUp, ThumbsDown } from 'lucide-react';
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
import React, { useState } from 'react';
import { Button } from '../ui/button';
import { useToast } from '@/hooks/use-toast';
import { logUserFeedbackInDb } from '@/app/data-actions';

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
    let confidenceText = "High";
    let confidenceExplanation = "I found exact matches in your data and the query was unambiguous.";

    if (confidence < 0.8) {
        confidenceColor = 'text-warning';
        confidenceText = "Medium";
        confidenceExplanation = "I found relevant data but had to make some assumptions to form an answer.";
    }
    if (confidence < 0.5) {
        confidenceColor = 'text-destructive';
        confidenceText = "Low";
        confidenceExplanation = "I was not very confident and had to make significant assumptions. Please verify this answer.";
    }

    const tooltipText = assumptions && assumptions.length > 0 
        ? `Assumptions made: ${assumptions.join(', ')}` 
        : 'No specific assumptions were made.';

    return (
        <TooltipProvider>
            <Tooltip delayDuration={100}>
                <TooltipTrigger asChild>
                    <div className="flex items-center gap-1 text-xs text-muted-foreground cursor-help">
                        <BrainCircuit className="h-3 w-3 text-accent" />
                        <span className={cn('font-semibold', confidenceColor)}>{confidencePercentage}% confident</span>
                    </div>
                </TooltipTrigger>
                <TooltipContent className="max-w-xs space-y-1">
                    <p className="font-bold">Confidence: <span className={confidenceColor}>{confidenceText}</span></p>
                    <p>{confidenceExplanation}</p>
                    <p className="italic pt-1">{tooltipText}</p>
                </TooltipContent>
            </Tooltip>
        </TooltipProvider>
    );
}

function FeedbackActions({ messageId }: { messageId: string }) {
    const [feedbackSent, setFeedbackSent] = useState(false);
    const { toast } = useToast();

    const handleFeedback = async (feedbackType: 'helpful' | 'unhelpful') => {
        setFeedbackSent(true);
        const result = await logUserFeedbackInDb({
            subjectId: messageId,
            subjectType: 'message',
            feedback: feedbackType
        });
        if (result.success) {
            toast({ description: "Thank you for your feedback!" });
        }
    };
    
    if (feedbackSent) {
      return <p className="text-xs text-muted-foreground">Thank you for your feedback!</p>;
    }

    return (
        <div className="flex items-center gap-2">
            <span className="text-xs text-muted-foreground">Was this response helpful?</span>
            <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleFeedback('helpful')}>
                <ThumbsUp className="h-4 w-4" />
            </Button>
            <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleFeedback('unhelpful')}>
                <ThumbsDown className="h-4 w-4" />
            </Button>
        </div>
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
                'h-9 w-9 shrink-0 rounded-full bg-gradient-to-br from-primary to-violet-500 flex items-center justify-center shadow-lg',
                isError && 'from-destructive/80 to-rose-500/80'
            )}
        >
            <Avatar className={cn('h-8 w-8 bg-card')}>
                <AvatarFallback className={cn('bg-transparent text-primary-foreground', isError && 'text-destructive-foreground')}>
                   {isError ? <AlertTriangle className="h-5 w-5" /> : <Bot className="h-5 w-5" />}
                </AvatarFallback>
            </Avatar>
        </motion.div>
    );
}

// Map component names to actual components
const componentMap: { [key: string]: React.ElementType } = {
    getDeadStockReport: DeadStockTable,
    getReorderSuggestions: ReorderList,
    getSupplierPerformanceAnalysis: SupplierPerformanceTable,
};

export function ChatMessage({
  message,
}: {
  message: Message;
}) {
  const isUserMessage = message.role === 'user';
  const isLoading = message.id === 'loading';
  
  const sanitizedContent = !isLoading ? DOMPurify.sanitize(message.content) : '';

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
        {!isUserMessage && <BotAvatar isError={message.is_error} />}
        
        <div className={cn(
            'relative max-w-xl rounded-2xl px-4 py-3 shadow-md space-y-2 text-base whitespace-pre-wrap selection:bg-primary/50',
            isUserMessage
                ? 'rounded-br-none bg-primary text-primary-foreground'
                : 'rounded-bl-none bg-card text-card-foreground',
            message.is_error && 'bg-destructive/10 border border-destructive/20 text-destructive'
        )}>
            {isLoading ? <LoadingIndicator /> : <div dangerouslySetInnerHTML={{ __html: sanitizedContent }} />}

            {!isUserMessage && !isLoading && !message.is_error &&(
            <ConfidenceDisplay confidence={message.confidence} assumptions={message.assumptions} />
            )}
        </div>

        {isUserMessage && (
          <Avatar className="h-9 w-9 shrink-0">
            <AvatarFallback>U</AvatarFallback>
          </Avatar>
        )}
      </div>
      
      {CustomComponent && message.component_props && (
          <div className={cn("max-w-xl w-full", !isUserMessage && "ml-12")}>
            <CustomComponent data={(message.component_props as any).data ?? message.component_props} />
          </div>
      )}

      {message.visualization && message.visualization.type !== 'none' && !CustomComponent && (
        <div className={cn("max-w-xl w-full", !isUserMessage && "ml-12")}>
          <DataVisualization
            visualization={message.visualization}
            title={(message.visualization as any)?.title}
          />
        </div>
      )}
      
       {!isUserMessage && !isLoading && !message.is_error && (
            <div className={cn("max-w-xl w-full flex justify-start", !isUserMessage && "ml-12")}>
                <FeedbackActions messageId={message.id} />
            </div>
        )}
    </motion.div>
  );
}
