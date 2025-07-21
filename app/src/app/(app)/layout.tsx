
'use client';
import { Sidebar, SidebarProvider, SidebarInset } from '@/components/ui/sidebar';
import { AppSidebar } from '@/components/nav/sidebar';
import ErrorBoundary from '@/components/error-boundary';
import { useState, useCallback } from 'react';
import { Toaster } from '@/components/ui/toaster';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AppPage } from '@/components/ui/page';
import { useAuth } from '@/context/auth-context';

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [resetKey, setResetKey] = useState(0);
  const [queryClient] = useState(() => new QueryClient());
  const { user } = useAuth();


  const handleReset = useCallback(() => {
    setResetKey((prevKey) => prevKey + 1);
  }, []);

  return (
    <QueryClientProvider client={queryClient}>
        <SidebarProvider>
        <div className="relative flex h-dvh w-full bg-background">
            <div className="absolute inset-0 -z-10 h-full w-full bg-background bg-[radial-gradient(theme(colors.border)_1px,transparent_1px)] [background-size:32px_32px]"></div>
            <Sidebar>
                <AppSidebar user={user} />
            </Sidebar>
            <SidebarInset className="flex flex-1 flex-col overflow-y-auto">
            <ErrorBoundary key={resetKey} onReset={handleReset}>
                <AppPage>
                  {children}
                </AppPage>
            </ErrorBoundary>
            </SidebarInset>
            <Toaster />
        </div>
        </SidebarProvider>
    </QueryClientProvider>
  );
}
