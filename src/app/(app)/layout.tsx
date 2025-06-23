'use client';
import { AppSidebar } from '@/components/app-sidebar';
import { ProtectedRoute } from '@/components/auth/protected-route';
import { SidebarProvider } from '@/components/ui/sidebar';

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <ProtectedRoute>
      <SidebarProvider>
        <div className="flex h-dvh w-full bg-background">
          <AppSidebar />
          <main className="flex flex-1 flex-col overflow-y-auto">
            {children}
          </main>
        </div>
      </SidebarProvider>
    </ProtectedRoute>
  );
}
