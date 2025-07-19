
'use client';

import { usePathname, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import {
  SidebarContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuButton,
  SidebarFooter,
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
  User,
  ShoppingCart,
  History
} from 'lucide-react';
import type { Conversation } from '@/types';


const mainNav = [
  { href: '/dashboard', label: 'Dashboard', icon: BarChart },
  { href: '/inventory', label: 'Inventory', icon: Package },
  { href: '/sales', label: 'Sales', icon: ShoppingCart },
  { href: '/suppliers', label: 'Suppliers', icon: Truck },
  { href: '/customers', label: 'Customers', icon: Users },
];

const analyticsNav = [
    { href: '/analytics/reordering', label: 'Reorder Analysis', icon: RefreshCw },
    { href: '/analytics/dead-stock', label: 'Dead Stock', icon: TrendingDown },
    { href: '/analytics/reports', label: 'Reports', icon: FileText },
];

const toolsNav = [
    { href: '/import', label: 'Import Data', icon: Import },
    { href: '/chat', label: 'AI Assistant', icon: MessageSquare },
];

const settingsNav = [
    { href: '/settings/profile', label: 'Profile', icon: User },
    { href: '/settings/integrations', label: 'Integrations', icon: PlusCircle },
];

function NavLink({ href, label, icon: Icon }: { href: string; label: string; icon: React.ElementType }) {
  const pathname = usePathname();
  const isActive = pathname.startsWith(href);

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
    const searchParams = useSearchParams();
    const isActive = pathname === `/chat` && searchParams.get('id') === conversation.id;
    return (
        <SidebarMenuSubItem>
            <Link href={`/chat?id=${conversation.id}`} legacyBehavior passHref>
                 <SidebarMenuSubButton isActive={isActive}>
                    <span className="truncate">{conversation.title}</span>
                </SidebarMenuSubButton>
            </Link>
        </SidebarMenuSubItem>
    );
}

export function AppSidebar() {
  const pathname = usePathname();
  const { data: conversations } = useQuery({
    queryKey: ['conversations'],
    queryFn: () => getConversations(),
  });

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
          {mainNav.map((item) => <NavLink key={item.href} {...item} />)}
          <Separator className="my-2" />
          
           <SidebarMenuItem>
                <SidebarMenuButton>
                    <BarChart />
                    <span>Analytics</span>
                </SidebarMenuButton>
                 <SidebarMenuSub>
                    {analyticsNav.map((item) => (
                        <SidebarMenuSubItem key={item.href}>
                             <Link href={item.href} legacyBehavior passHref>
                                <SidebarMenuSubButton isActive={pathname.startsWith(item.href)}>
                                    <item.icon/>
                                    <span>{item.label}</span>
                                </SidebarMenuSubButton>
                            </Link>
                        </SidebarMenuSubItem>
                    ))}
                </SidebarMenuSub>
            </SidebarMenuItem>

           <Separator className="my-2" />
           {toolsNav.map((item) => <NavLink key={item.href} {...item} />)}

            {(conversations && conversations.length > 0) && (
              <>
                <Separator className="my-2" />
                <SidebarMenuItem>
                    <SidebarMenuButton>
                        <History />
                        <span>History</span>
                    </SidebarMenuButton>
                    <SidebarMenuSub>
                        {conversations.map((convo) => <ConversationLink key={convo.id} conversation={convo} />)}
                    </SidebarMenuSub>
                </SidebarMenuItem>
              </>
            )}
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
                                <SidebarMenuSubButton isActive={pathname.startsWith(item.href)}>
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
