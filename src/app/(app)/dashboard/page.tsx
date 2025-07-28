
import { getDashboardData, getMorningBriefing, getCompanySettings } from '@/app/data-actions';
import { DashboardClientPage } from './dashboard-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { AlertTriangle } from 'lucide-react';
import type { DashboardMetrics } from '@/types';
import { logger } from '@/lib/logger';

export const dynamic = 'force-dynamic';

const emptyMetrics: DashboardMetrics = {
    total_revenue: 0,
    revenue_change: 0,
    total_sales: 0,
    sales_change: 0,
    new_customers: 0,
    customers_change: 0,
    dead_stock_value: 0,
    sales_over_time: [],
    top_selling_products: [],
    inventory_summary: {
        total_value: 0,
        in_stock_value: 0,
        low_stock_value: 0,
        dead_stock_value: 0,
    },
};

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: { [key: string]: string | string[] | undefined };
}) {
    const dateRange = typeof searchParams?.range === 'string' ? searchParams.range : '90d';
    let metrics: DashboardMetrics;
    let briefing;
    let settings;
    let metricsError = null;

    try {
        // Fetch data in parallel for better performance
        [metrics, briefing, settings] = await Promise.all([
            getDashboardData(dateRange),
            getMorningBriefing(dateRange),
            getCompanySettings(),
        ]);
        
        if ((metrics as any).error) {
            metricsError = (metrics as any).error;
            metrics = emptyMetrics; // Use empty metrics on error
        }

    } catch (error) {
        logger.error('Failed to fetch dashboard data', { error });
        metrics = emptyMetrics;
        metricsError = 'Could not connect to the data service.';
        // Provide default fallback data so the page can still render
        briefing = { greeting: 'Welcome!', summary: 'Could not load insights. Please try again later.' };
        settings = { currency: 'USD', timezone: 'UTC' };
    }


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
                            We couldn't load the metrics for your dashboard. This might be a temporary issue. Please try refreshing the page. If the problem persists, it may be because you have not yet imported any data.
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
