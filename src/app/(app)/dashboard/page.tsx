
import { AlertTriangle, DollarSign, Package, Users, ShoppingCart, BarChart, AlertCircle, TrendingUp, RefreshCw } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { getDashboardData } from '@/app/data-actions';
import Link from 'next/link';
import { SalesTrendChart } from '@/components/dashboard/sales-trend-chart';
import { InventoryCategoryChart } from '@/components/dashboard/inventory-category-chart';
import { TopCustomersChart } from '@/components/dashboard/top-customers-chart';
import { DashboardHeaderControls } from '@/components/dashboard/header-controls';
import { AppPage, AppPageHeader } from '@/components/ui/page';

function formatCurrency(value: number) {
    if (Math.abs(value) >= 1_000_000) {
        return `$${(value / 1_000_000).toFixed(1)}M`;
    }
    if (Math.abs(value) >= 1_000) {
        return `$${(value / 1_000).toFixed(1)}k`;
    }
    return `$${value.toFixed(2)}`;
}

function formatNumber(value: number) {
    if (Math.abs(value) >= 1_000_000) {
        return `${(value / 1_000_000).toFixed(1)}M`;
    }
    if (Math.abs(value) >= 1_000) {
        return `${(value / 1_000).toFixed(1)}k`;
    }
    return value.toString();
}

function MetricCard({
    title,
    value,
    icon: Icon,
    label,
    href,
    className
}: {
    title: string;
    value: string;
    icon: React.ElementType;
    label?: string;
    href: string;
    className?: string;
}) {
  return (
    <Link href={href} className={cn("group block", className)}>
        <Card className="relative h-full transition-all duration-300 group-hover:bg-accent/50 group-hover:shadow-lg group-hover:-translate-y-1">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
            <Icon className="h-5 w-5 text-muted-foreground transition-transform group-hover:scale-110 group-hover:text-primary" />
            </CardHeader>
            <CardContent>
            <div className="text-3xl font-bold text-foreground">{value}</div>
            {label && <p className="text-xs text-muted-foreground">{label}</p>}
            </CardContent>
        </Card>
    </Link>
  );
}

function ErrorDisplay({ error }: { error: Error }) {
    return (
        <Card className="col-span-1 md:col-span-2 lg:col-span-4 border-destructive/50 bg-destructive/10">
            <CardHeader>
                <CardTitle className="flex items-center gap-2 text-destructive">
                    <AlertTriangle className="h-5 w-5" />
                    Could Not Load Dashboard Data
                </CardTitle>
                <CardDescription className="text-destructive/80">
                    There was an issue fetching the dashboard metrics. This might be a temporary problem or an issue with your account configuration.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <p className="text-sm font-mono bg-destructive/20 p-2 rounded-md">{error.message}</p>
            </CardContent>
        </Card>
    )
}

export default async function DashboardPage({
  searchParams,
}: {
  searchParams?: { range?: string };
}) {
    let data;
    let fetchError: Error | null = null;
    const dateRange = searchParams?.range || '30d';
    
    try {
        data = await getDashboardData(dateRange);
    } catch (e) {
        fetchError = e as Error;
    }

    return (
        <AppPage>
            <AppPageHeader title="Dashboard">
                <DashboardHeaderControls />
            </AppPageHeader>

            {fetchError ? (
                <ErrorDisplay error={fetchError} />
            ) : data ? (
                <div className="space-y-6">
                    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                            <MetricCard
                            href="/analytics"
                            title="Total Revenue"
                            value={formatCurrency(data.totalSalesValue)}
                            icon={BarChart}
                            label={`Last ${dateRange.replace('d', '')} days`}
                        />
                            <MetricCard
                            href="/analytics"
                            title="Total Profit"
                            value={formatCurrency(data.totalProfit)}
                            icon={TrendingUp}
                            label={`Last ${dateRange.replace('d', '')} days`}
                        />
                            <MetricCard
                            href="/analytics"
                            title="Average Order Value"
                            value={formatCurrency(data.averageOrderValue)}
                            icon={DollarSign}
                            label={`Last ${dateRange.replace('d', '')} days`}
                        />
                        <MetricCard
                            href="/analytics"
                            title="Return Rate"
                            value={`${data.returnRate.toFixed(1)}%`}
                            icon={RefreshCw}
                            label={`Last ${dateRange.replace('d', '')} days`}
                        />
                            <MetricCard
                            href="/inventory"
                            title="Inventory Value"
                            value={formatCurrency(data.totalInventoryValue)}
                            icon={Package}
                            label="Current value of all stock"
                            className="sm:col-span-2"
                        />
                        <MetricCard
                            href="/alerts"
                            title="Low Stock SKUs"
                            value={formatNumber(data.lowStockItemsCount)}
                            icon={AlertCircle}
                            label="Items below reorder point"
                            className="sm:col-span-2"
                        />
                    </div>

                    <div className="grid grid-cols-1 gap-4 lg:grid-cols-4">
                        <SalesTrendChart data={data.salesTrendData} className="lg:col-span-4" />
                        <TopCustomersChart data={data.topCustomersData} className="lg:col-span-3" />
                        <InventoryCategoryChart data={data.inventoryByCategoryData} className="lg:col-span-1" />
                    </div>
                </div>
            ) : null}
        </AppPage>
    );
}
