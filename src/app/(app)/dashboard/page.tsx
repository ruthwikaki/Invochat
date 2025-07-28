

import { getDashboardData, getMorningBriefing, getCompanySettings } from '@/app/data-actions';
import { DashboardClientPage } from './dashboard-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { AlertTriangle } from 'lucide-react';

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

    const metricsError = (metrics as any).error;

    return (
        <AppPage>
            <AppPageHeader
                title="Dashboard"
                description="Here's a high-level overview of your business performance."
            />
            <div className="mt-6">
                {metricsError ? (
                    <Alert variant="destructive">
                        <AlertTriangle className="h-4 w-4" />
                        <AlertTitle>Error Loading Dashboard Data</AlertTitle>
                        <AlertDescription>
                            We couldn't load the metrics for your dashboard. This might be a temporary issue with our data analytics service. Please try refreshing the page in a few moments.
                        </AlertDescription>
                    </Alert>
                ) : (
                    <DashboardClientPage
                        initialMetrics={metrics}
                        settings={settings}
                        initialBriefing={briefing}
                    />
                )}
            </div>
        </AppPage>
    );
}

