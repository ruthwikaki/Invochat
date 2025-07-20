
import { getDashboardData, getMorningBriefing } from '@/app/data-actions';
import { DashboardClientPage } from './dashboard/dashboard-client-page';
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
            >
                {/* This functionality is handled by the client component now */}
            </AppPageHeader>
            <DashboardClientPage 
                initialMetrics={metrics} 
                initialBriefing={briefing}
            />
        </>
    );
}
