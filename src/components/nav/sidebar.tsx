
'use client';

import { usePathname } from 'next/navigation';
import Link from 'next/link';
import {
  Sidebar,
  SidebarContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuButton,
  SidebarFooter,
  SidebarTrigger,
  SidebarMenuSub,
  SidebarMenuSubButton,
  SidebarMenuSubItem
} from '@/components/ui/sidebar';
import { InvoChatLogo } from '@/components/invochat-logo';
import { Separator } from '@/components/ui/separator';
import { UserAccountNav } from './user-account-nav';
import { getConversations } from '@/app/actions';
import { useQuery } from '@tanstack/react-query';
import {
  BarChart,
  MessageSquare,
  Package,
  FileText,
  Users,
  Settings,
  PlusCircle,
  TrendingDown,
  RefreshCw,
  Truck,
  Import,
  FileQuestion,
  LifeBuoy,
  LogOut,
  ChevronDown
} from 'lucide-react';
import type { Conversation } from '@/types';
import { Button } from '../ui/button';


const mainNav = [
  { href: '/dashboard', label: 'Dashboard', icon: BarChart },
  { href: '/inventory', label: 'Inventory', icon: Package },
  { href: '/suppliers', label: 'Suppliers', icon: Truck },
  { href: '/reordering', label: 'Reordering', icon: RefreshCw },
  { href: '/dead-stock', label: 'Dead Stock', icon: TrendingDown },
];

const settingsNav = [
    { href: '/settings/profile', label: 'Profile', icon: Users },
    { href: '/settings/integrations', label: 'Integrations', icon: PlusCircle },
];

function NavLink({ href, label, icon: Icon }: { href: string; label: string; icon: React.ElementType }) {
  const pathname = usePathname();
  const isActive = pathname === href || pathname.startsWith(`${href}/`);

  return (
    <SidebarMenuItem>
      <Link href={href} legacyBehavior passHref>
        <SidebarMenuButton isActive={isActive} tooltip={label}>
          <Icon />
          <span>{label}</span>
        </SidebarMenuButton>
      </Link>
    </SidebarMenuItem>
  );
}

function ConversationLink({ conversation }: { conversation: Conversation }) {
    const pathname = usePathname();
    const isActive = pathname === `/chat` && new URLSearchParams(window.location.search).get('id') === conversation.id;
    return (
        <SidebarMenuSubItem>
            <Link href={`/chat?id=${conversation.id}`} legacyBehavior passHref>
                 <SidebarMenuSubButton isActive={isActive}>
                    <span>{conversation.title}</span>
                </SidebarMenuSubButton>
            </Link>
        </SidebarMenuSubItem>
    );
}

export function AppSidebar() {
  const pathname = usePathname();
  const { data: conversations, isLoading } = useQuery({
    queryKey: ['conversations'],
    queryFn: () => getConversations(),
    refetchOnWindowFocus: false,
  });
  const isChatActive = pathname === '/chat';

  return (
    <>
      <SidebarHeader>
        <div className="flex items-center gap-2">
            <InvoChatLogo className="h-8 w-8 text-primary" />
            <span className="text-lg font-semibold">InvoChat</span>
        </div>
      </SidebarHeader>
      
      <SidebarContent>
        <SidebarMenu>
          <SidebarMenuItem>
             <Link href="/chat" legacyBehavior passHref>
                <SidebarMenuButton isActive={isChatActive}>
                    <MessageSquare />
                    <span>New Chat</span>
                </SidebarMenuButton>
             </Link>
          </SidebarMenuItem>
          {conversations && conversations.length > 0 && (
             <SidebarMenuItem>
                <SidebarMenuButton>
                    <ChevronDown className="h-4 w-4" />
                    <span>Recent Chats</span>
                </SidebarMenuButton>
                <SidebarMenuSub>
                {conversations?.slice(0, 5).map(convo => (
                    <ConversationLink key={convo.id} conversation={convo} />
                ))}
                </SidebarMenuSub>
             </SidebarMenuItem>
          )}
          <Separator className="my-2" />
          {mainNav.map((item) => <NavLink key={item.href} {...item} />)}
          <Separator className="my-2" />
           <NavLink href="/import" label="Import Data" icon={Import} />
        </SidebarMenu>
      </SidebarContent>

      <SidebarFooter>
        <SidebarMenu>
            <SidebarMenuItem>
                <SidebarMenuButton>
                    <Settings />
                    <span>Settings</span>
                </SidebarMenuButton>
                <SidebarMenuSub>
                    {settingsNav.map((item) => (
                        <SidebarMenuSubItem key={item.href}>
                             <Link href={item.href} legacyBehavior passHref>
                                <SidebarMenuSubButton isActive={pathname === item.href}>
                                    <item.icon/>
                                    <span>{item.label}</span>
                                </SidebarMenuSubButton>
                            </Link>
                        </SidebarMenuSubItem>
                    ))}
                </SidebarMenuSub>
            </SidebarMenuItem>
        </SidebarMenu>
        <Separator />
        <UserAccountNav />
      </SidebarFooter>
    </>
  );
}
