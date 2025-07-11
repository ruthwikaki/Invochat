
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
  ShoppingCart,
  ClipboardList,
  HeartPulse,
} from 'lucide-react';
import { SidebarMenu, SidebarMenuItem, SidebarMenuButton } from '@/components/ui/sidebar';

const menuItems = [
  { href: '/dashboard', label: 'Dashboard', icon: Home },
  { href: '/chat', label: 'Chat', icon: MessageSquare, exact: false },
  { href: '/inventory', label: 'Inventory', icon: Package },
  { href: '/sales', label: 'Sales', icon: ShoppingCart },
  { href: '/reports/reordering', label: 'Reorder Report', icon: ClipboardList },
  { href: '/reports/dead-stock', label: 'Dead Stock', icon: TrendingDown },
  { href: '/reports/abc-analysis', label: 'ABC Analysis', icon: BarChart },
  { href: '/reports/profit-leaks', label: 'Profit Leaks', icon: Lightbulb },
   { href: '/reports/health-score', label: 'Health Score', icon: HeartPulse },
  { href: '/suppliers', label: 'Suppliers', icon: Truck },
];

export function MainNavigation() {
  const pathname = usePathname();

  return (
    <SidebarMenu>
      {menuItems.map((item) => {
        const isActive = item.exact === false
            ? pathname.startsWith(item.href)
            : pathname === item.href;
          
        return (
          <SidebarMenuItem key={item.href}>
            <SidebarMenuButton asChild isActive={isActive}>
              <Link href={item.href} prefetch={false}>
                <item.icon />
                {item.label}
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        );
      })}
    </SidebarMenu>
  );
}
