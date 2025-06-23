'use client';

import { usePathname, useRouter } from 'next/navigation';
import Link from 'next/link';
import {
  AlertCircle,
  BarChart,
  Home,
  LogOut,
  MessageSquare,
  Moon,
  Package,
  Sun,
  TrendingDown,
  Truck,
  Upload,
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
import { useTheme } from 'next-themes';
import { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem } from './ui/dropdown-menu';
import { useAuth } from '@/context/auth-context';

export function AppSidebar() {
  const pathname = usePathname();
  const { setTheme } = useTheme();
  const { user, logout } = useAuth();
  const router = useRouter();

  const handleLogout = async () => {
    await logout();
    router.push('/login');
  };

  const menuItems = [
    { href: '/dashboard', label: 'Dashboard', icon: Home },
    { href: '/chat', label: 'Chat with InvoChat', icon: MessageSquare },
    { href: '/inventory', label: 'Inventory', icon: Package },
    { href: '/import', label: 'Import Data', icon: Upload },
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
          <SidebarMenuItem>
            <DropdownMenu>
                <DropdownMenuTrigger asChild>
                    <SidebarMenuButton>
                        <Avatar className="h-7 w-7">
                            <AvatarImage src={user?.photoURL || undefined} alt={user?.displayName || 'User'} data-ai-hint="user avatar" />
                            <AvatarFallback>{(user?.email?.charAt(0) || '').toUpperCase()}</AvatarFallback>
                        </Avatar>
                        <span className="truncate">{user?.displayName || user?.email}</span>
                    </SidebarMenuButton>
                </DropdownMenuTrigger>
                <DropdownMenuContent side="right" align="end">
                    <DropdownMenuItem onClick={handleLogout}>
                        <LogOut className="mr-2 h-4 w-4" />
                        <span>Log out</span>
                    </DropdownMenuItem>
                </DropdownMenuContent>
            </DropdownMenu>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  );
}
