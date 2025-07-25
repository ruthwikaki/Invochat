
import { ReactNode } from 'react';
import { Sidebar, SidebarProvider, SidebarInset } from '@/components/ui/sidebar';
import { AppSidebar } from '@/components/nav/sidebar';
import { QueryClientProvider } from '@/context/query-client-provider';

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <QueryClientProvider>
      <SidebarProvider>
        <div className="relative flex h-dvh w-full bg-background">
          <div className="absolute inset-0 -z-10 h-full w-full bg-background bg-[radial-gradient(theme(colors.border)_1px,transparent_1px)] [background-size:32px_32px]"></div>
          <Sidebar>
            <AppSidebar />
          </Sidebar>
          <SidebarInset>
              <main className="flex-1 overflow-y-auto p-4 sm:p-6 lg:p-8">
                  {children}
              </main>
          </SidebarInset>
        </div>
      </SidebarProvider>
    </QueryClientProvider>
  );
}
