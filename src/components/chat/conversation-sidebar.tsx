
'use client';

import type { Conversation } from '@/types';
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { cn } from '@/lib/utils';
import { InvochatLogo } from '../invochat-logo';
import { MessageSquarePlus, MessageSquareText, Star, Trash2 } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';

type ConversationSidebarProps = {
  conversations: Conversation[];
  activeConversationId?: string;
};

export function ConversationSidebar({
  conversations,
  activeConversationId,
}: ConversationSidebarProps) {
  return (
    <aside className="hidden md:flex flex-col w-80 h-full border-r bg-background">
      <div className="p-4 border-b flex items-center justify-between shrink-0">
        <div className="flex items-center gap-2">
            <InvochatLogo className="h-7 w-7" />
            <h1 className="text-xl font-semibold">InvoChat</h1>
        </div>
        <Button asChild variant="outline" size="sm">
          <Link href="/chat">
            <MessageSquarePlus className="mr-2 h-4 w-4"/>
            New Chat
          </Link>
        </Button>
      </div>

      <ScrollArea className="flex-1">
        <nav className="p-2 space-y-1">
          {conversations.map((convo) => (
            <Link
              key={convo.id}
              href={`/chat?id=${convo.id}`}
              className={cn(
                'group flex flex-col p-2 rounded-md transition-colors w-full text-left',
                activeConversationId === convo.id
                  ? 'bg-primary/10 text-primary'
                  : 'hover:bg-muted'
              )}
            >
              <div className="flex justify-between items-center">
                <span className="text-sm font-medium truncate flex items-center gap-2">
                    <MessageSquareText className="h-4 w-4 shrink-0" />
                    {convo.title}
                </span>
                {convo.is_starred && <Star className="h-4 w-4 text-yellow-500 fill-yellow-400" />}
              </div>
              <span className="text-xs text-muted-foreground mt-1 ml-6">
                {formatDistanceToNow(new Date(convo.last_accessed_at), { addSuffix: true })}
              </span>
            </Link>
          ))}
        </nav>
      </ScrollArea>
       <div className="p-2 border-t">
          <Button variant="ghost" className="w-full justify-start text-muted-foreground" disabled>
            <Trash2 className="mr-2 h-4 w-4"/>
            Clear all conversations
          </Button>
       </div>
    </aside>
  );
}
