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
  Settings,
  Sun,
  TrendingDown,
  Truck,
  Upload,
  User,
  Beaker,
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
} from './ui/sidebar';
import { useTheme } from 'next-themes';
import { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem } from './ui/dropdown-menu';
import { useAuth } from '@/context/auth-context';
import { Avatar, AvatarFallback } from './ui/avatar';
import { Skeleton } from './ui/skeleton';

export function AppSidebar() {
  const pathname = usePathname();
  const { setTheme } = useTheme();
  const { user, signOut, loading } = useAuth();
  const router = useRouter();

  const handleSignOut = async () => {
    await signOut();
    // Refresh the page. The middleware will catch the unauthenticated state
    // and redirect to the login page.
    router.refresh();
  };

  const menuItems = [
    { href: '/dashboard', label: 'Dashboard', icon: Home },
    { href: '/chat', label: 'Chat with ARVO', icon: MessageSquare },
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
          <span className="text-lg font-semibold">ARVO</span>
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
      <SidebarFooter className="mt-auto flex flex-col gap-2">
         <div className="flex items-center gap-2 p-2 border-t">
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
          <SidebarMenuItem>
            <SidebarMenuButton asChild isActive={pathname === '/test-supabase'}>
              <Link href="/test-supabase">
                <Beaker />
                <span>Connection Test</span>
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
                <DropdownMenuItem onClick={() => setTheme('system')}>
                  System
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton>
              <Settings />
              <span>Settings</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  );
}
