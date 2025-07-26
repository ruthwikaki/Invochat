
import { getDashboardData, getMorningBriefing, getCompanySettings } from '@/app/data-actions';
import { DashboardClientPage } from '@/components/dashboard/dashboard-client-page';
import { AppPageContainer } from '@/components/ui/page';

export const dynamic = 'force-dynamic';

export default async function DashboardPage({
  searchParams,
}: {
  searchParams?: { [key: string]: string | string[] | undefined };
}) {
    const dateRange = typeof searchParams?.range === 'string' ? searchParams.range : '90d';
    const [metrics, briefing, settings] = await Promise.all([
        getDashboardData(dateRange),
        getMorningBriefing(dateRange),
        getCompanySettings(),
    ]);
    
    return (
        <AppPageContainer
            title="Dashboard"
            description="Here's a high-level overview of your business performance."
        >
            <DashboardClientPage 
                initialMetrics={metrics} 
                settings={settings}
                initialBriefing={briefing}
            />
        </AppPageContainer>
    );
}
