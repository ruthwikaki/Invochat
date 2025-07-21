'use client';
import { Sidebar, SidebarProvider, SidebarInset } from '@/components/ui/sidebar';
import { AppSidebar } from '@/components/nav/sidebar';
import ErrorBoundary from '@/components/error-boundary';
import { Toaster } from '@/components/ui/toaster';
import { QueryClientProvider } from '@/context/query-client-provider';
import { AppPage } from '@/components/ui/page';
import { useAuth } from '@/context/auth-context';
import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { Skeleton } from '@/components/ui/skeleton';

function AppLoadingSkeleton() {
    return (
        <div className="flex h-dvh w-full">
            <div className="w-16 md:w-64 h-full p-2 border-r">
                <Skeleton className="h-10 w-full mb-4" />
                <div className="space-y-2">
                    <Skeleton className="h-8 w-full" />
                    <Skeleton className="h-8 w-full" />
                    <Skeleton className="h-8 w-full" />
                </div>
            </div>
            <div className="flex-1 p-8">
                <Skeleton className="h-12 w-1/3 mb-8" />
                <Skeleton className="h-64 w-full" />
            </div>
        </div>
    )
}

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
    const { user, loading } = useAuth();
    const router = useRouter();

    useEffect(() => {
        if (!loading && !user) {
            router.push('/login');
        }
    }, [user, loading, router]);
    
    if (loading || !user) {
        return <AppLoadingSkeleton />;
    }

  return (
    <QueryClientProvider>
        <SidebarProvider>
        <div className="relative flex h-dvh w-full bg-background">
            <div className="absolute inset-0 -z-10 h-full w-full bg-background bg-[radial-gradient(theme(colors.border)_1px,transparent_1px)] [background-size:32px_32px]"></div>
            <Sidebar>
                <AppSidebar />
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
