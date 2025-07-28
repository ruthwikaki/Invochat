
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
    let metrics: DashboardMetrics = emptyMetrics;
    let briefing;
    let settings;
    let metricsError = null;

    try {
        // Fetch data in parallel for better performance
        // If any of these fail, the catch block will handle it.
        [metrics, briefing, settings] = await Promise.all([
            getDashboardData(dateRange),
            getMorningBriefing(dateRange),
            getCompanySettings(),
        ]);
        
        // The getDashboardData action now returns an error property if it fails internally
        if ((metrics as any).error) {
            // This case handles when a new user has no data, which causes the DB function to fail.
            // We log the error but don't show it to the user, providing a clean empty state instead.
            logger.warn('Dashboard metrics failed to load, likely due to no data. Showing empty state.', { error: (metrics as any).error });
            metrics = emptyMetrics; 
        }

    } catch (error) {
        logger.error('Failed to fetch dashboard data', { error });
        // This catch block handles more severe, unexpected errors.
        metricsError = 'Could not connect to the data service. The service may be temporarily unavailable.';
        metrics = emptyMetrics;
        briefing = { greeting: 'Welcome!', summary: 'Could not load insights at this time.' };
        settings = { currency: 'USD', timezone: 'UTC', dead_stock_days: 90, fast_moving_days: 30, overstock_multiplier: 3, high_value_threshold: 100000, predictive_stock_days: 7, tax_rate: 0 };
    }


    return (
        <AppPage>
            <AppPageHeader
                title="Dashboard"
                description="Here's a high-level overview of your business performance."
            />
            <div className="mt-6">
                {metricsError && (
                    <Alert variant="destructive" className="mb-6">
                        <AlertTriangle className="h-4 w-4" />
                        <AlertTitle>Could Not Load Dashboard Metrics</AlertTitle>
                        <AlertDescription>
                            {metricsError}
                        </AlertDescription>
                    </Alert>
                )}
                <DashboardClientPage
                    initialMetrics={metrics}
                    settings={settings}
                    initialBriefing={briefing}
                />
            </div>
        </AppPage>
    );
}
