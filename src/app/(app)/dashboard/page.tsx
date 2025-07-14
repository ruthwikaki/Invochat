
import { getDashboardData, getMorningBriefing } from '@/app/data-actions';
import { DashboardClientPage } from './dashboard-client-page';

export default async function DashboardPage() {
    // For now, we fetch with a default date range.
    // In a real app, this would be a parameter from the UI.
    const dateRange = '90d';
    
    // Fetch data in parallel
    const [metrics, briefing] = await Promise.all([
        getDashboardData(dateRange),
        getMorningBriefing(dateRange),
    ]);

    return (
        <DashboardClientPage initialMetrics={metrics} initialBriefing={briefing} />
    );
}
