import { Skeleton } from '@/components/ui/skeleton';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default function DashboardLoading() {
  return (
    <AppPage>
      <AppPageHeader
        title="Dashboard"
        description="Here's a high-level overview of your business performance."
      >
        <Skeleton className="h-10 w-[180px]" />
      </AppPageHeader>
      <div className="space-y-6">
        {/* Quick Actions Skeleton */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <Skeleton className="h-20 w-full" />
          <Skeleton className="h-20 w-full" />
          <Skeleton className="h-20 w-full" />
          <Skeleton className="h-20 w-full" />
        </div>

        {/* Morning Briefing Skeleton */}
        <Skeleton className="h-24 w-full" />

        {/* Stat Cards Skeleton */}
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          <Skeleton className="h-28 w-full" />
          <Skeleton className="h-28 w-full" />
          <Skeleton className="h-28 w-full" />
          <Skeleton className="h-28 w-full" />
        </div>

        {/* Charts Skeleton */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <Skeleton className="h-80 w-full" />
          <Skeleton className="h-80 w-full" />
        </div>

        {/* Inventory Summary Skeleton */}
        <Skeleton className="h-40 w-full" />
      </div>
    </AppPage>
  );
}
