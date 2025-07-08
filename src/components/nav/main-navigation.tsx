
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
  ClipboardList,
  RefreshCw,
  Warehouse,
  Plug,
  Settings,
  Users,
  ShoppingCart,
  ShieldCheck,
} from 'lucide-react';
import { SidebarMenu, SidebarMenuItem, SidebarMenuButton } from '@/components/ui/sidebar';

const menuItems = [
  { href: '/dashboard', label: 'Dashboard', icon: Home },
  { href: '/chat', label: 'Chat', icon: MessageSquare, exact: false },
  { href: '/analytics', label: 'Strategic Reports', icon: BarChart },
  { href: '/inventory', label: 'Inventory', icon: Package },
  { href: '/sales', label: 'Sales', icon: ShoppingCart },
  { href: '/purchase-orders', label: 'Purchase Orders', icon: ClipboardList },
  { href: '/reordering', label: 'Reorder Suggestions', icon: RefreshCw },
  { href: '/insights', label: 'Insights', icon: Lightbulb },
  { href: '/dead-stock', label: 'Dead Stock', icon: TrendingDown },
  { href: '/suppliers', label: 'Suppliers', icon: Truck },
  { href: '/customers', label: 'Customers', icon: Users },
  { href: '/alerts', label: 'Alerts', icon: AlertCircle },
  { href: '/locations', label: 'Locations', icon: Warehouse },
  { href: '/settings/integrations', label: 'Integrations', icon: Plug },
  { href: '/test-supabase', label: 'System Health', icon: ShieldCheck },
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
