
import { getDashboardData, getMorningBriefing } from '@/app/data-actions';
import { DashboardClientPage } from './(app)/dashboard/dashboard-client-page';
import { Sidebar, SidebarProvider, SidebarInset } from '@/components/ui/sidebar';
import { AppSidebar } from '@/components/nav/sidebar';
import ErrorBoundary from '@/components/error-boundary';
import { Toaster } from '@/components/ui/toaster';

export default async function DashboardPage() {
    const dateRange = '90d';
    
    // Fetch data in parallel
    const [metrics, briefing] = await Promise.all([
        getDashboardData(dateRange),
        getMorningBriefing(dateRange),
    ]);

    return (
      <SidebarProvider>
      <div className="relative flex h-dvh w-full bg-background">
        <div className="absolute inset-0 -z-10 h-full w-full bg-background bg-[radial-gradient(theme(colors.border)_1px,transparent_1px)] [background-size:32px_32px]"></div>
        <Sidebar>
            <AppSidebar />
        </Sidebar>
        <SidebarInset className="flex flex-1 flex-col overflow-y-auto">
          <ErrorBoundary onReset={() => {}}>
            <div className="flex-1 p-4 md:p-6 lg:p-8">
              <DashboardClientPage initialMetrics={metrics} initialBriefing={briefing} />
            </div>
          </ErrorBoundary>
        </SidebarInset>
        <Toaster />
      </div>
    </SidebarProvider>
    );
}
