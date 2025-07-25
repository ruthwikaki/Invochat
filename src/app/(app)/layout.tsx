
import { ReactNode, useState } from 'react';
import { Sidebar, SidebarProvider, SidebarInset } from '@/components/ui/sidebar';
import { AppSidebar } from '@/components/nav/sidebar';
import ErrorBoundary from '@/components/error-boundary';
import { Toaster } from '@/components/ui/toaster';
import { QueryClientProvider } from '@/context/query-client-provider';
import { AppInitializer } from '@/components/app-initializer';

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <AppInitializer>
        <QueryClientProvider>
        <SidebarProvider>
        <div className="relative flex h-dvh w-full bg-background">
            <div className="absolute inset-0 -z-10 h-full w-full bg-background bg-[radial-gradient(theme(colors.border)_1px,transparent_1px)] [background-size:32px_32px]"></div>
            <Sidebar>
                <AppSidebar />
            </Sidebar>
            <SidebarInset className="flex flex-1 flex-col">
              <ErrorBoundary>
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
    </AppInitializer>
  );
}
