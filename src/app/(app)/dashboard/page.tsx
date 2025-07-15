
import { getDashboardData, getMorningBriefing } from '@/app/data-actions';
import { DashboardClientPage } from './dashboard-client-page';
import { AppPage } from '@/components/ui/page';

export default async function DashboardPage() {
    const dateRange = '90d'; // Default date range
    const [metrics, briefing] = await Promise.all([
        getDashboardData(dateRange),
        getMorningBriefing(dateRange),
    ]);
    
    return (
        <AppPage>
            <DashboardClientPage 
                initialMetrics={metrics} 
                initialBriefing={briefing}
            />
        </AppPage>
    );
}
