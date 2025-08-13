

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
} from '@/components/ui/sidebar';
import { AIventoryLogo } from '@/components/aiventory-logo';
import { Separator } from '@/components/ui/separator';
import { UserAccountNav } from './user-account-nav';
import { getConversations } from '@/app/data-actions';
import { useQuery } from '@tanstack/react-query';
import {
  BarChart,
  MessageSquare,
  Package,
  FileText,
  Users,
  Settings,
  TrendingDown,
  RefreshCw,
  Truck,
  Import,
  Sparkles,
  TestTubeDiagonal,
  GraduationCap,
} from 'lucide-react';
import type { Conversation } from '@/types';
import { useAuth } from '@/context/auth-context';
import { AlertCenter } from '../alerts/alert-center';


const mainNav = [
  { href: '/dashboard', label: 'Dashboard', icon: BarChart },
  { href: '/inventory', label: 'Inventory', icon: Package },
  { href: '/sales', label: 'Sales', icon: FileText },
  { href: '/suppliers', label: 'Suppliers', icon: Truck },
  { href: '/customers', label: 'Customers', icon: Users },
  { href: '/purchase-orders', label: 'Purchase Orders', icon: Package },
];

const reportsNav = [
    { href: '/analytics/reordering', label: 'Reordering', icon: RefreshCw },
    { href: '/analytics/dead-stock', label: 'Dead Stock', icon: TrendingDown },
    { href: '/analytics/supplier-performance', label: 'Suppliers', icon: Truck },
    { href: '/analytics/inventory-turnover', label: 'Turnover', icon: Package },
    { href: '/analytics/ai-insights', label: 'AI Insights', icon: Sparkles },
    { href: '/analytics/advanced-reports', label: 'Advanced Reports', icon: TestTubeDiagonal },
    { href: '/analytics/ai-performance', label: 'AI Performance', icon: GraduationCap },
];

function NavLink({ href, label, icon: Icon }: { href: string; label: string; icon: React.ElementType }) {
  const pathname = usePathname();
  const isActive = pathname.startsWith(href) && (href !== '/dashboard' || pathname === '/dashboard');

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
        <SidebarMenuSub>
            <Link href={`/chat?id=${conversation.id}`} legacyBehavior passHref>
                 <SidebarMenuSubButton isActive={isActive} className="w-full">
                    <span className="truncate">{conversation.title || 'Untitled Chat'}</span>
                </SidebarMenuSubButton>
            </Link>
        </SidebarMenuSub>
    );
}

export function AppSidebar() {
  const pathname = usePathname();
  const { user } = useAuth();
  const { data: conversations } = useQuery({
    queryKey: ['conversations'],
    queryFn: getConversations,
    enabled: !!user,
  });

  return (
    <>
      <SidebarHeader>
        <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
                <AIventoryLogo className="h-8 w-8 text-primary" />
                <span className="text-lg font-semibold">
                    <span className="text-primary">AI</span><span className="text-foreground">ventory</span>
                </span>
            </div>
             <div className="flex items-center gap-1">
                <AlertCenter />
             </div>
        </div>
      </SidebarHeader>
      
      <SidebarContent>
        <SidebarMenu>
          {mainNav.map((item) => <NavLink key={item.href} {...item} />)}
          
          <Separator className="my-2" />
          
           <SidebarMenuItem>
              <SidebarMenuButton disabled className="font-semibold text-muted-foreground !bg-transparent h-auto p-2 text-xs">
                  Analytics
              </SidebarMenuButton>
               <SidebarMenuSub>
                {reportsNav.map((item) => <NavLink key={item.href} {...item} />)}
              </SidebarMenuSub>
           </SidebarMenuItem>

          <Separator className="my-2" />
            
           <SidebarMenuItem>
                <Link href="/import" legacyBehavior passHref>
                    <SidebarMenuButton isActive={pathname.startsWith('/import')}>
                        <Import />
                        <span>Import</span>
                    </SidebarMenuButton>
                </Link>
           </SidebarMenuItem>

            <SidebarMenuItem>
                <Link href="/chat" legacyBehavior passHref>
                    <SidebarMenuButton isActive={pathname.startsWith('/chat')}>
                        <MessageSquare />
                        <span>AI Chat</span>
                    </SidebarMenuButton>
                </Link>
                {(conversations && conversations.length > 0) && (
                    <SidebarMenuSub>
                        {conversations.slice(0, 5).map((convo) => <ConversationLink key={convo.id} conversation={convo} />)}
                    </SidebarMenuSub>
                )}
            </SidebarMenuItem>

        </SidebarMenu>
      </SidebarContent>

      <SidebarFooter>
        <Separator />
         <SidebarMenuItem>
            <Link href="/settings/profile" legacyBehavior passHref>
                <SidebarMenuButton isActive={pathname.startsWith('/settings')}>
                    <Settings />
                    <span>Settings</span>
                </SidebarMenuButton>
            </Link>
        </SidebarMenuItem>
        <UserAccountNav user={user} />
      </SidebarFooter>
    </>
  );
}


