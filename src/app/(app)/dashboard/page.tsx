
import { getDashboardData, getMorningBriefing, getCompanySettings } from '@/app/data-actions';
import { DashboardClientPage } from './dashboard-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export const dynamic = 'force-dynamic';

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: { [key: string]: string | string[] | undefined };
}) {
    const dateRange = typeof searchParams?.range === 'string' ? searchParams.range : '90d';
    
    // Fetch data in parallel for better performance
    const [metrics, briefing, settings] = await Promise.all([
        getDashboardData(dateRange),
        getMorningBriefing(dateRange),
        getCompanySettings(),
    ]);
    
    return (
        <AppPage>
            <AppPageHeader
                title="Dashboard"
                description="Here's a high-level overview of your business performance."
            />
            <div className="mt-6">
                <DashboardClientPage 
                    initialMetrics={metrics} 
                    settings={settings}
                    initialBriefing={briefing}
                />
            </div>
        </AppPage>
    );
}
