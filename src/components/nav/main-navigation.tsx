
'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  Home,
  MessageSquare,
  Package,
  Lightbulb,
  TrendingDown,
  Truck,
  BarChart,
  AlertCircle,
  Pyramid,
} from 'lucide-react';
import { SidebarMenu, SidebarMenuItem, SidebarMenuButton } from '@/components/ui/sidebar';

const menuItems = [
  { href: '/dashboard', label: 'Dashboard', icon: Home },
  { href: '/chat', label: 'Chat with InvoChat', icon: MessageSquare },
  { href: '/analytics', label: 'Analytics', icon: Pyramid },
  { href: '/inventory', label: 'Inventory', icon: Package },
  { href: '/insights', label: 'Insights', icon: Lightbulb },
  { href: '/dead-stock', label: 'Dead Stock', icon: TrendingDown },
  { href: '/suppliers', label: 'Suppliers', icon: Truck },
  { href: '/alerts', label: 'Alerts', icon: AlertCircle },
];

export function MainNavigation() {
  const pathname = usePathname();

  return (
    <SidebarMenu>
      {menuItems.map((item) => (
        <SidebarMenuItem key={item.href}>
          <SidebarMenuButton asChild isActive={pathname.startsWith(item.href)}>
            <Link href={item.href} prefetch={false}>
              <item.icon />
              {item.label}
            </Link>
          </SidebarMenuButton>
        </SidebarMenuItem>
      ))}
    </SidebarMenu>
  );
}
