
import { AlertTriangle, DollarSign, Package, TrendingDown, Truck, BarChart, AlertCircle } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { cn } from '@/lib/utils';
import { getDashboardData } from '@/app/data-actions';
import Link from 'next/link';
import { SalesTrendChart } from '@/components/dashboard/sales-trend-chart';
import { InventoryCategoryChart } from '@/components/dashboard/inventory-category-chart';

function formatCurrency(value: number) {
    if (Math.abs(value) >= 1_000_000) {
        return `$${(value / 1_000_000).toFixed(1)}M`;
    }
    if (Math.abs(value) >= 1_000) {
        return `$${(value / 1_000).toFixed(1)}k`;
    }
    return `$${value.toFixed(0)}`;
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
        <Card className="relative h-full transition-all duration-300 group-hover:bg-card/95 group-hover:shadow-lg group-hover:-translate-y-1">
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

export default async function DashboardPage() {
    let data;
    let fetchError: Error | null = null;
    
    try {
        data = await getDashboardData();
    } catch (e: any) {
        fetchError = e;
    }

    return (
        <div className="relative min-h-full overflow-hidden">
            <div className="animate-background-pan absolute inset-0 z-0 bg-[length:200%_200%] bg-gradient-to-br from-primary/5 via-background to-background" />
            <div className="relative z-10 p-4 sm:p-6 lg:p-8 space-y-6">
                <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                        <SidebarTrigger className="md:hidden" />
                        <h1 className="text-2xl font-semibold">Dashboard</h1>
                    </div>
                </div>

                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    {fetchError ? (
                        <ErrorDisplay error={fetchError} />
                    ) : data ? (
                        <>
                            <MetricCard
                                href="/inventory"
                                title="Total Inventory Value"
                                value={formatCurrency(data.inventoryValue)}
                                icon={DollarSign}
                                className="sm:col-span-2"
                            />
                            <MetricCard
                                href="/analytics"
                                title="Total Sales"
                                value={formatCurrency(data.totalSalesValue)}
                                icon={BarChart}
                                label="All-time sales data"
                                className="sm:col-span-2"
                            />
                            <MetricCard
                                href="/dead-stock"
                                title="Dead Stock Value"
                                value={formatCurrency(data.deadStockValue)}
                                icon={TrendingDown}
                            />
                            <MetricCard
                                href="/alerts"
                                title="Low Stock Items"
                                value={data.lowStockCount.toString()}
                                icon={AlertCircle}
                                label="Items below reorder point"
                            />
                            <MetricCard
                                href="/inventory"
                                title="Total SKUs"
                                value={data.totalSKUs.toString()}
                                icon={Package}
                            />
                            <MetricCard
                                href="/suppliers"
                                title="Total Suppliers"
                                value={data.totalSuppliers.toString()}
                                icon={Truck}
                            />
                            
                            <SalesTrendChart data={data.salesTrendData} className="sm:col-span-2 lg:col-span-4" />
                            <InventoryCategoryChart data={data.inventoryByCategoryData} className="sm:col-span-2 lg:col-span-4" />
                        </>
                    ) : null}
                </div>
            </div>
        </div>
    );
}
