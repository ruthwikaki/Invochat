import { Skeleton } from '@/components/ui/skeleton';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Card, CardContent, CardHeader } from '@/components/ui/card';

interface TablePageSkeletonProps {
  title: string;
  description: string;
  headerAction?: React.ReactNode;
}

export function TablePageSkeleton({ title, description, headerAction }: TablePageSkeletonProps) {
  return (
    <AppPage>
      <AppPageHeader title={title} description={description}>
        {headerAction || <Skeleton className="h-10 w-24" />}
      </AppPageHeader>
      
      {/* Analytics Cards Skeleton */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
      </div>

      <Card>
        <CardHeader>
          {/* Search/Filter Controls Skeleton */}
          <div className="flex flex-col md:flex-row items-center gap-2">
            <Skeleton className="h-10 flex-1 w-full" />
            <Skeleton className="h-10 w-full md:w-[180px]" />
            <Skeleton className="h-10 w-[120px]" />
          </div>
        </CardHeader>
        <CardContent>
          {/* Table Skeleton */}
          <div className="space-y-2">
            {Array.from({ length: 10 }).map((_, i) => (
              <Skeleton key={i} className="h-12 w-full" />
            ))}
          </div>
        </CardContent>
      </Card>
    </AppPage>
  );
}
