
'use client';
import { AppSidebar } from '@/components/app-sidebar';
import { SidebarProvider } from '@/components/ui/sidebar';
import { useAuth } from '@/context/auth-context';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { Skeleton } from '@/components/ui/skeleton';

function AppLoadingScreen() {
  return (
    <div className="flex h-dvh w-full">
      <div className="hidden md:flex flex-col h-full w-64 border-r p-4 gap-4">
        <Skeleton className="h-10 w-3/4" />
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
        <div className="flex-grow" />
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
      </div>
      <div className="flex-1 p-8">
        <Skeleton className="h-12 w-1/3 mb-8" />
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            <Skeleton className="h-32" />
            <Skeleton className="h-32" />
            <Skeleton className="h-32" />
            <Skeleton className="h-32" />
        </div>
      </div>
    </div>
  )
}

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { user, userProfile, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    // This effect acts as a route guard. It will run whenever the auth state changes.
    if (loading) {
      return; // Do nothing while the auth state is being resolved.
    }

    if (!user) {
      // If loading is complete and there's no user, they should be on the login page.
      router.replace('/login');
    } else if (!userProfile) {
      // If there IS a user but they don't have a company profile in Supabase,
      // they need to complete the setup.
      router.replace('/company-setup');
    }
    // If a user and userProfile both exist, they are allowed to see the content.
  }, [user, userProfile, loading, router]);

  // This is the gatekeeper. It shows a loading screen until the AuthContext
  // has finished resolving the user's full state (including their company profile).
  // This prevents rendering the app in a partial state and causing incorrect redirects.
  if (loading || !user || !userProfile) {
    return <AppLoadingScreen />;
  }

  // Only when auth is fully resolved and profile exists, render the main app.
  return (
    <SidebarProvider>
      <div className="flex h-dvh w-full bg-background">
        <AppSidebar />
        <main className="flex flex-1 flex-col overflow-y-auto">
          {children}
        </main>
      </div>
    </SidebarProvider>
  );
}
