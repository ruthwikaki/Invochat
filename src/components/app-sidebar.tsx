'use client';

import { usePathname } from 'next/navigation';
import Link from 'next/link';
import {
  AlertCircle,
  BarChart,
  Home,
  MessageSquare,
  Package,
  Settings,
  TrendingDown,
  Truck,
} from 'lucide-react';
import { InvoChatLogo } from './invochat-logo';
import { Avatar, AvatarFallback, AvatarImage } from './ui/avatar';
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuButton,
} from './ui/sidebar';

export function AppSidebar() {
  const pathname = usePathname();

  const menuItems = [
    { href: '/dashboard', label: 'Dashboard', icon: Home },
    { href: '/chat', label: 'Chat with InvoChat', icon: MessageSquare },
    { href: '/inventory', label: 'Inventory', icon: Package },
    { href: '/dead-stock', label: 'Dead Stock', icon: TrendingDown },
    { href: '/suppliers', label: 'Suppliers', icon: Truck },
    { href: '/analytics', label: 'Analytics', icon: BarChart },
    { href: '/alerts', label: 'Alerts', icon: AlertCircle },
  ];

  return (
    <Sidebar>
      <SidebarHeader>
        <div className="flex items-center gap-2">
          <InvoChatLogo />
          <span className="text-lg font-semibold">InvoChat</span>
        </div>
      </SidebarHeader>
      <SidebarContent>
        <SidebarMenu>
          {menuItems.map((item) => (
            <SidebarMenuItem key={item.href}>
              <SidebarMenuButton asChild isActive={pathname.startsWith(item.href)}>
                <Link href={item.href}>
                  <item.icon />
                  {item.label}
                </Link>
              </SidebarMenuButton>
            </SidebarMenuItem>
          ))}
        </SidebarMenu>
      </SidebarContent>
      <SidebarFooter>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton>
              <Settings />
              Settings
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton>
              <Avatar className="h-7 w-7">
                <AvatarImage src="https://placehold.co/100x100.png" alt="User" data-ai-hint="user avatar" />
                <AvatarFallback>U</AvatarFallback>
              </Avatar>
              <span>User Profile</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  );
}
