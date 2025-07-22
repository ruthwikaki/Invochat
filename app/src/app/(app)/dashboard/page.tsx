
import { getDashboardData, getMorningBriefing } from '@/app/data-actions';
import { DashboardClientPage } from '@/components/dashboard/dashboard-client-page';
import { AppPageHeader } from '@/components/ui/page';
import { Skeleton } from '@/components/ui/skeleton';
import { Suspense } from 'react';

export const dynamic = 'force-dynamic';

function DashboardLoadingSkeleton() {
    return (
        <div className="space-y-6">
            <div className="flex flex-col md:flex-row items-start justify-between gap-4">
                 <Skeleton className="h-10 w-48" />
                 <Skeleton className="h-10 w-[180px]" />
            </div>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <Skeleton className="h-24 w-full" />
                <Skeleton className="h-24 w-full" />
                <Skeleton className="h-24 w-full" />
                <Skeleton className="h-24 w-full" />
            </div>
            <Skeleton className="h-28 w-full" />
             <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                <Skeleton className="h-24 w-full" />
                <Skeleton className="h-24 w-full" />
                <Skeleton className="h-24 w-full" />
                <Skeleton className="h-24 w-full" />
            </div>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <Skeleton className="h-80 w-full" />
                <Skeleton className="h-80 w-full" />
            </div>
        </div>
    )
}

async function DashboardData({ dateRange }: { dateRange: string }) {
    const [metrics, briefing] = await Promise.all([
        getDashboardData(dateRange),
        getMorningBriefing(dateRange),
    ]);
    
    return (
        <DashboardClientPage 
            initialMetrics={metrics} 
            initialBriefing={briefing}
        />
    )
}

export default async function DashboardPage({
  searchParams,
}: {
  searchParams?: { [key: string]: string | string[] | undefined };
}) {
    const dateRange = typeof searchParams?.range === 'string' ? searchParams.range : '90d';
    
    return (
        <>
            <AppPageHeader
                title="Dashboard"
                description="Here's a high-level overview of your business performance."
            />
            <Suspense fallback={<DashboardLoadingSkeleton />}>
                <DashboardData dateRange={dateRange} />
            </Suspense>
        </>
    );
}
