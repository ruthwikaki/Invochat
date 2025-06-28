
'use client';

import type { Conversation } from '@/types';
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Separator } from '@/components/ui/separator';
import { cn } from '@/lib/utils';
import { InvochatLogo } from '../invochat-logo';
import { MessageSquarePlus, MessageSquareText, Star, Home, Package, Lightbulb, TrendingDown, Truck, BarChart, AlertCircle, LogOut, Moon, Settings, Sun, Database, ShieldCheck } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import { Sidebar, SidebarFooter, SidebarMenu, SidebarMenuItem, SidebarMenuButton } from '@/components/ui/sidebar';
import { usePathname } from 'next/navigation';
import { useAuth } from '@/context/auth-context';
import { useTheme } from 'next-themes';
import { Avatar, AvatarFallback } from '../ui/avatar';
import { Skeleton } from '../ui/skeleton';
import { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem } from '../ui/dropdown-menu';


type ConversationSidebarProps = {
  conversations: Conversation[];
  activeConversationId?: string;
};

export function ConversationSidebar({
  conversations,
  activeConversationId,
}: ConversationSidebarProps) {
    const pathname = usePathname();
    const { setTheme } = useTheme();
    const { user, signOut, loading } = useAuth();

    const handleSignOut = async () => {
        try {
        await signOut();
        } catch (error) {
        console.error('Sign out error:', error);
        }
    };

    const mainMenuItems = [
        { href: '/dashboard', label: 'Dashboard', icon: Home },
        { href: '/inventory', label: 'Inventory', icon: Package },
        { href: '/import', label: 'Insights', icon: Lightbulb },
        { href: '/dead-stock', label: 'Dead Stock', icon: TrendingDown },
        { href: '/suppliers', label: 'Suppliers', icon: Truck },
        { href: '/analytics', label: 'Analytics', icon: BarChart },
        { href: '/alerts', label: 'Alerts', icon: AlertCircle },
    ];

    const settingsMenuItems = [
        { href: '/database', label: 'Database Explorer', icon: Database },
        { href: '/test-supabase', label: 'System Health', icon: ShieldCheck },
        { href: '/settings', label: 'Settings', icon: Settings },
    ];


  return (
    <Sidebar className="w-80 flex-col border-r bg-background">
      <div className="p-4 border-b flex items-center justify-between shrink-0">
        <div className="flex items-center gap-2">
            <InvochatLogo className="h-7 w-7" />
            <h1 className="text-xl font-semibold">InvoChat</h1>
        </div>
        <Button asChild variant="outline" size="sm" className={cn(pathname === '/chat' && !activeConversationId && 'bg-primary/10')}>
          <Link href="/chat">
            <MessageSquarePlus className="mr-2 h-4 w-4"/>
            New Chat
          </Link>
        </Button>
      </div>

      <ScrollArea className="flex-1">
        <div className="p-2 space-y-1">
            <p className="px-2 text-xs font-semibold text-muted-foreground tracking-wider">Chats</p>
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
            {conversations.length === 0 && <p className="p-2 text-xs text-muted-foreground">No recent chats.</p>}
        </div>
        
        <Separator className="my-2" />

        <div className="p-2 space-y-1">
            <p className="px-2 text-xs font-semibold text-muted-foreground tracking-wider">Navigate</p>
             <SidebarMenu>
                {mainMenuItems.map((item) => (
                    <SidebarMenuItem key={item.href}>
                    <SidebarMenuButton asChild isActive={pathname.startsWith(item.href) && item.href !== '/chat'}>
                        <Link href={item.href} prefetch={false}>
                        <item.icon />
                        {item.label}
                        </Link>
                    </SidebarMenuButton>
                    </SidebarMenuItem>
                ))}
            </SidebarMenu>
        </div>
      </ScrollArea>

       <SidebarFooter className="mt-auto flex flex-col gap-2 border-t">
         <div className="flex items-center gap-2 p-2">
          {loading ? (
            <>
              <Skeleton className="h-8 w-8 rounded-full" />
              <Skeleton className="h-4 w-24" />
            </>
          ) : user ? (
            <>
              <Avatar className="h-8 w-8">
                <AvatarFallback>{user.email?.charAt(0).toUpperCase()}</AvatarFallback>
              </Avatar>
              <span className="text-sm truncate">{user.email}</span>
              <SidebarMenuButton variant="ghost" size="icon" className="h-8 w-8 ml-auto" onClick={handleSignOut}>
                <LogOut />
              </SidebarMenuButton>
            </>
          ) : null}
        </div>
        <SidebarMenu>
            {settingsMenuItems.map((item) => (
                <SidebarMenuItem key={item.href}>
                    <SidebarMenuButton asChild isActive={pathname === item.href}>
                    <Link href={item.href} prefetch={false}>
                        <item.icon />
                        <span>{item.label}</span>
                    </Link>
                    </SidebarMenuButton>
                </SidebarMenuItem>
            ))}
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
                <DropdownMenuItem onClick={() => setTheme('system')}>
                  System
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  );
}
