
import { ReactNode } from 'react';
import { Sidebar, SidebarProvider, SidebarInset } from '@/components/ui/sidebar';
import { AppSidebar } from '@/components/nav/sidebar';
import { QueryClientProvider } from '@/context/query-client-provider';
import { getCurrentUser } from '@/lib/auth-helpers';
import { redirect } from 'next/navigation';
import { logError } from '@/lib/error-handler';

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  try {
    const user = await getCurrentUser();
    // This check is critical. If the user object exists but has no company_id,
    // it means the database setup trigger failed. Redirect to a recovery page.
    if (user && !user.app_metadata.company_id) {
      return redirect('/env-check');
    }
    // If there is no user session at all, redirect to login.
    if (!user) {
        return redirect('/login');
    }
  } catch (error) {
      logError(error, { context: 'AppLayout auth check failed' });
      // If the database call itself fails, we can't check the user.
      // Redirect to login with an error message indicating a server issue.
      return redirect('/login?error=Could not connect to the authentication service. Please try again later.');
  }

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
