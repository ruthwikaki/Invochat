
import { Sidebar, SidebarProvider, SidebarInset } from '@/components/ui/sidebar';
import { AppSidebar } from '@/components/nav/sidebar';
import ErrorBoundary from '@/components/error-boundary';
import { Toaster } from '@/components/ui/toaster';
import { QueryClientProvider } from '@/context/query-client-provider';
import { AppPage } from '@/components/ui/page';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import type { User } from '@/types';

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const cookieStore = cookies();
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value;
        },
      },
    }
  );
  const { data: { user } } = await supabase.auth.getUser();

  return (
    <QueryClientProvider>
        <SidebarProvider>
        <div className="relative flex h-dvh w-full bg-background">
            <div className="absolute inset-0 -z-10 h-full w-full bg-background bg-[radial-gradient(theme(colors.border)_1px,transparent_1px)] [background-size:32px_32px]"></div>
            <Sidebar>
                <AppSidebar user={user as User} />
            </Sidebar>
            <SidebarInset className="flex flex-1 flex-col overflow-y-auto">
            <ErrorBoundary>
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
