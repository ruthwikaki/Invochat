
'use client';
import { AppSidebar } from '@/components/app-sidebar';
import { SidebarProvider } from '@/components/ui/sidebar';
import ErrorBoundary from '@/components/error-boundary';
import { useState, useCallback } from 'react';

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
    <div className="flex h-dvh w-full bg-background">
        <AppSidebar />
        <main className="flex flex-1 flex-col overflow-y-auto">
        <ErrorBoundary key={resetKey} onReset={handleReset}>
            {children}
        </ErrorBoundary>
        </main>
    </div>
    </SidebarProvider>
  );
}
