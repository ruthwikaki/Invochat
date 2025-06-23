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
    if (!loading) {
      if (!user) {
        // No Firebase user, must log in.
        router.push('/auth/login');
      } else if (user && !userProfile) {
        // Firebase user exists, but no Supabase profile.
        // Must complete company setup.
        router.push('/auth/company-setup');
      }
      // If user and userProfile exist, we stay and render children.
    }
  }, [user, userProfile, loading, router]);

  // Show loading screen while checking auth state or if user is not fully set up.
  if (loading || !user || !userProfile) {
    return <AppLoadingScreen />;
  }

  // Only render the full app layout if we have a Firebase user AND a Supabase profile.
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
