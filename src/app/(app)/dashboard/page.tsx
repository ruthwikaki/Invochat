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
    total_orders: 0,
    orders_change: 0,
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

const testMetrics: DashboardMetrics = {
    total_revenue: 123456,
    revenue_change: 12.5,
    total_orders: 42,
    orders_change: -5.2,
    new_customers: 7,
    customers_change: 10,
    dead_stock_value: 34567,
    sales_over_time: [{ date: '2025-08-01', revenue: 12345 }, { date: '2025-08-02', revenue: 23456 }],
    top_selling_products: [{ product_id: 'prod-1', product_name: 'Test Product', image_url: null, quantity_sold: 10, total_revenue: 123456 }],
    inventory_summary: {
        total_value: 500000,
        in_stock_value: 300000,
        low_stock_value: 150000,
        dead_stock_value: 50000,
    }
};

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: { [key: string]: string | string[] | undefined };
}) {
    if (process.env.TEST_MODE === 'true') {
        const settings = await getCompanySettings();
        const briefing = { greeting: 'Welcome!', summary: 'This is a test summary.', cta: { text: 'View Report', link: '#' } };
        return (
             <AppPage>
                <AppPageHeader
                    title="Dashboard"
                    description="Here's a high-level overview of your business performance."
                />
                <div className="mt-6">
                    <DashboardClientPage
                        initialMetrics={testMetrics}
                        settings={settings}
                        initialBriefing={briefing}
                    />
                </div>
            </AppPage>>
        );
    }
    
    const dateRange = typeof searchParams?.range === 'string' ? searchParams.range : '90d';
    let metrics: DashboardMetrics = emptyMetrics;
    let briefing;
    let settings;
    let metricsError = null;

    try {
        // Fetch all data in parallel
        const [metricsData, briefingData, settingsData] = await Promise.all([
            getDashboardData(dateRange),
            getMorningBriefing(dateRange),
            getCompanySettings(),
        ]);
        
        metrics = metricsData || emptyMetrics;
        briefing = briefingData;
        settings = settingsData;

    } catch (error: any) {
        logger.error('Failed to fetch dashboard data', { error: error.message });
        
        // Check if this is the expected error for new users (relation does not exist)
        const isNewUserError = error.message?.includes('relation') && error.message?.includes('does not exist');

        if (!isNewUserError) {
            // For unexpected errors, show the error banner
            metricsError = 'Could not load your dashboard analytics. The data service may be temporarily unavailable. Please try again later.';
        }
        
        // In either error case (new user or unexpected), fall back to safe, empty data to prevent crashes
        metrics = emptyMetrics;
        briefing = { greeting: 'Welcome!', summary: 'Import your data to get started with AI insights.', cta: { text: 'Import Data', link: '/import' } };
        settings = { company_id: '', created_at: '', dead_stock_days: 90, fast_moving_days: 30, overstock_multiplier: 3, high_value_threshold: 100000, predictive_stock_days: 7, currency: 'USD', tax_rate: 0, timezone: 'UTC', updated_at: null, alert_settings: {} };
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
