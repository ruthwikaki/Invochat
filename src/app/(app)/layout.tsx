
'use client';
import { Sidebar, SidebarProvider, SidebarInset } from '@/components/ui/sidebar';
import { AppSidebar } from '@/components/nav/sidebar';
import ErrorBoundary from '@/components/error-boundary';
import { useState, useCallback } from 'react';
import { Toaster } from '@/components/ui/toaster';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [resetKey, setResetKey] = useState(0);
  const [queryClient] = useState(() => new QueryClient());


  const handleReset = useCallback(() => {
    setResetKey((prevKey) => prevKey + 1);
  }, []);

  return (
    <QueryClientProvider client={queryClient}>
        <SidebarProvider>
        <div className="relative flex h-dvh w-full bg-background">
            <div className="absolute inset-0 -z-10 h-full w-full bg-background bg-[radial-gradient(theme(colors.border)_1px,transparent_1px)] [background-size:32px_32px]"></div>
            <Sidebar>
                <AppSidebar />
            </Sidebar>
            <SidebarInset className="flex flex-1 flex-col">
              <ErrorBoundary key={resetKey} onReset={handleReset}>
                  <main className="flex-1 overflow-y-auto p-4 sm:p-6 lg:p-8">
                    <div className="mx-auto max-w-7xl space-y-6">
                      {children}
                    </div>
                  </main>
              </ErrorBoundary>
            </SidebarInset>
            <Toaster />
        </div>
        </SidebarProvider>
    </QueryClientProvider>
  );
}
