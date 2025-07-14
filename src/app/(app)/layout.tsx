
'use client';
import { Sidebar, SidebarProvider, SidebarTrigger, SidebarInset } from '@/components/ui/sidebar';
import { AppSidebar } from '@/components/nav/sidebar';
import ErrorBoundary from '@/components/error-boundary';
import { useState, useCallback } from 'react';
import { Toaster } from '@/components/ui/toaster';

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [resetKey, setResetKey] = useState(0);

  const handleReset = useCallback(() => {
    setResetKey((prevKey) => prevKey + 1);
  }, []);

  return (
    <SidebarProvider>
      <div className="relative flex h-dvh w-full bg-background">
        <div className="absolute inset-0 -z-10 h-full w-full bg-background bg-[radial-gradient(theme(colors.border)_1px,transparent_1px)] [background-size:32px_32px]"></div>
        <Sidebar>
            <AppSidebar />
        </Sidebar>
        <SidebarInset className="flex flex-1 flex-col overflow-y-auto">
          <ErrorBoundary key={resetKey} onReset={handleReset}>
            <div className="flex-1 p-4 md:p-6 lg:p-8">
             {children}
            </div>
          </ErrorBoundary>
        </SidebarInset>
        <Toaster />
      </div>
    </SidebarProvider>
  );
}
