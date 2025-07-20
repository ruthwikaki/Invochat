import { getDashboardData, getMorningBriefing } from '@/app/data-actions';
import { DashboardClientPage } from '@/components/dashboard/dashboard-client-page';
import { AppPageHeader } from '@/components/ui/page';

export default async function DashboardPage({
  searchParams,
}: {
  searchParams?: { [key: string]: string | string[] | undefined };
}) {
    const dateRange = typeof searchParams?.range === 'string' ? searchParams.range : '90d';
    const [metrics, briefing] = await Promise.all([
        getDashboardData(dateRange),
        getMorningBriefing(dateRange),
    ]);
    
    return (
        <>
            <AppPageHeader
                title="Dashboard"
                description="Here's a high-level overview of your business performance."
            />
            <DashboardClientPage 
                initialMetrics={metrics} 
                initialBriefing={briefing}
            />
        </>
    );
}