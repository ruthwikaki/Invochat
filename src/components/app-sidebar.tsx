
'use client';

import { usePathname, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import {
  Moon,
  Settings,
  Sun,
  Database,
  ShieldCheck,
  Upload,
  MessageSquarePlus,
  MessageSquareText,
  Star,
  DatabaseZap,
} from 'lucide-react';
import { InvoChatLogo } from './invochat-logo';
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuButton,
  SidebarTrigger,
} from './ui/sidebar';
import { useTheme } from 'next-themes';
import { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem } from './ui/dropdown-menu';
import { UserAccountNav } from '@/components/nav/user-account-nav';
import { MainNavigation } from '@/components/nav/main-navigation';
import { getConversations } from '@/app/actions';
import type { Conversation } from '@/types';
import { useEffect, useState } from 'react';
import { Button } from './ui/button';
import { ScrollArea } from './ui/scroll-area';
import { Separator } from './ui/separator';
import { cn } from '@/lib/utils';
import { formatDistanceToNow } from 'date-fns';


export function AppSidebar() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const activeConversationId = searchParams.get('id');
  const { setTheme } = useTheme();
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchConversations() {
      try {
        setLoading(true);
        const convos = await getConversations();
        setConversations(convos);
      } catch (error) {
        console.error("Failed to fetch conversations", error);
      } finally {
        setLoading(false);
      }
    }
    fetchConversations();
  }, [pathname, activeConversationId]); // Refetch when navigation changes


  return (
    <Sidebar className="w-80 flex-col border-r bg-card">
      <SidebarHeader>
        <div className="flex items-center gap-2">
          <InvoChatLogo className="h-7 w-7" />
          <h1 className="text-xl font-semibold">ARVO</h1>
        </div>
        <SidebarTrigger className="md:hidden" />
      </SidebarHeader>

      <div className="p-2">
         <Button asChild variant="outline" size="sm" className={cn('w-full', pathname === '/chat' && !activeConversationId && 'bg-primary/10')}>
          <Link href="/chat">
            <MessageSquarePlus className="mr-2 h-4 w-4"/>
            New Chat
          </Link>
        </Button>
      </div>
      
      <ScrollArea className="flex-1">
        {/* Main App Navigation */}
        <div className="p-2 space-y-1">
            <p className="px-2 text-xs font-semibold text-muted-foreground tracking-wider">Navigate</p>
            <MainNavigation />
        </div>
        
        <Separator className="my-2" />

        {/* Chat History */}
        <div className="p-2 space-y-1">
            <p className="px-2 text-xs font-semibold text-muted-foreground tracking-wider">Chats</p>
            {loading ? (
                <p className="p-2 text-xs text-muted-foreground">Loading chats...</p>
            ) : conversations.length > 0 ? (
                conversations.map((convo) => (
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
                ))
            ) : (
                <p className="p-2 text-xs text-muted-foreground">No recent chats.</p>
            )}
        </div>
      </ScrollArea>

      <SidebarFooter className="mt-auto flex flex-col gap-2 border-t">
        <UserAccountNav />
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton asChild isActive={pathname === '/import'}>
              <Link href="/import" prefetch={false}>
                <Upload />
                <span>Data Importer</span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton asChild isActive={pathname === '/database'}>
              <Link href="/database" prefetch={false}>
                <Database />
                <span>Database Explorer</span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton asChild isActive={pathname === '/database-setup'}>
              <Link href="/database-setup" prefetch={false}>
                <DatabaseZap />
                <span>Database Setup</span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton asChild isActive={pathname === '/test-supabase'}>
              <Link href="/test-supabase" prefetch={false}>
                <ShieldCheck />
                <span>System Health</span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
             <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <SidebarMenuButton>
                  <Sun className="h-4 w-4 rotate-0 scale-100 transition-all dark:-rotate-90 dark:scale-0" />
                  <Moon className="absolute h-4 w-4 rotate-90 scale-0 transition-all dark:rotate-0 dark:scale-100" />
                  <span>Toggle Theme</span>
                </SidebarMenuButton>
              </DropdownMenuTrigger>
              <DropdownMenuContent side="right" align="end">
                <DropdownMenuItem onClick={() => setTheme('light')}>
                  Light
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => setTheme('dark')}>
                  Dark
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton asChild isActive={pathname === '/settings'}>
              <Link href="/settings" prefetch={false}>
                <Settings />
                <span>Settings</span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  );
}