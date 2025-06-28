
'use client';

import { usePathname } from 'next/navigation';
import Link from 'next/link';
import {
  Moon,
  Settings,
  Sun,
  Database,
  ShieldCheck,
  Upload,
} from 'lucide-react';
import { InvochatLogo } from './invochat-logo';
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
import { UserAccountNav } from '@/components/nav/user-account-nav';
import { MainNavigation } from '@/components/nav/main-navigation';


export function AppSidebar() {
  const pathname = usePathname();
  const { setTheme } = useTheme();

  return (
    <Sidebar>
      <SidebarHeader>
        <div className="flex items-center gap-2">
          <InvochatLogo />
          <span className="text-lg font-semibold">InvoChat</span>
        </div>
      </SidebarHeader>
      <SidebarContent>
        <MainNavigation />
      </SidebarContent>
      <SidebarFooter className="mt-auto flex flex-col gap-2">
         <UserAccountNav />
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton asChild isActive={pathname === '/import'}>
              <Link href="/import" prefetch={false}>
                <Upload />
                <span>Data Importer</span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton asChild isActive={pathname === '/database'}>
              <Link href="/database" prefetch={false}>
                <Database />
                <span>Database Explorer</span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton asChild isActive={pathname === '/test-supabase'}>
              <Link href="/test-supabase" prefetch={false}>
                <ShieldCheck />
                <span>System Health</span>
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
            <SidebarMenuButton asChild isActive={pathname === '/settings'}>
              <Link href="/settings" prefetch={false}>
                <Settings />
                <span>Settings</span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  );
}
