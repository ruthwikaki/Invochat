
import { AlertTriangle, DollarSign, Package, TrendingDown, Truck, BarChart, AlertCircle } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { cn } from '@/lib/utils';
import { getDashboardData } from '@/app/data-actions';
import Link from 'next/link';

function formatCurrency(value: number) {
    if (Math.abs(value) >= 1_000_000) {
        return `$${(value / 1_000_000).toFixed(1)}M`;
    }
    if (Math.abs(value) >= 1_000) {
        return `$${(value / 1_000).toFixed(1)}k`;
    }
    return `$${value.toFixed(0)}`;
}

function MetricCard({ title, value, icon: Icon, variant = 'default', label }: { title: string; value: string; icon: React.ElementType; variant?: 'default' | 'destructive' | 'success' | 'warning'; label?: string; }) {
  const variantClasses = {
      default: '',
      destructive: 'border-destructive/50 text-destructive',
      success: 'border-success/50 text-success',
      warning: 'border-warning/50 text-warning',
  }

  return (
    <Card className={cn('transition-all hover:shadow-md hover:-translate-y-1', variantClasses[variant])}>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
        <Icon className="h-5 w-5 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{value}</div>
        {label && <p className="text-xs text-muted-foreground">{label}</p>}
      </CardContent>
    </Card>
  );
}

function ErrorDisplay({ error }: { error: Error }) {
    return (
        <Card className="col-span-1 md:col-span-2 lg:col-span-3 border-destructive/50">
            <CardHeader>
                <CardTitle className="flex items-center gap-2 text-destructive">
                    <AlertTriangle className="h-5 w-5" />
                    Could Not Load Dashboard Data
                </CardTitle>
                <CardDescription>
                    There was an issue fetching the dashboard metrics. This might be a temporary problem or an issue with your account configuration.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <p className="text-sm font-mono bg-muted p-2 rounded-md">{error.message}</p>
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
        <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <SidebarTrigger className="md:hidden" />
                    <h1 className="text-2xl font-semibold">Dashboard</h1>
                </div>
            </div>

            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                {fetchError ? (
                    <ErrorDisplay error={fetchError} />
                ) : data ? (
                    <>
                        <Link href="/inventory" className="transition-all hover:shadow-md hover:-translate-y-1">
                            <MetricCard
                                title="Total Inventory Value"
                                value={formatCurrency(data.inventoryValue)}
                                icon={DollarSign}
                                variant="success"
                            />
                        </Link>
                        <Link href="/analytics" className="transition-all hover:shadow-md hover:-translate-y-1">
                            <MetricCard
                                title="Total Sales"
                                value={formatCurrency(data.totalSalesValue)}
                                icon={BarChart}
                                label="All-time sales data"
                            />
                        </Link>
                         <Link href="/dead-stock" className="transition-all hover:shadow-md hover:-translate-y-1">
                            <MetricCard
                                title="Dead Stock Value"
                                value={formatCurrency(data.deadStockValue)}
                                icon={TrendingDown}
                                variant="destructive"
                            />
                        </Link>
                         <Link href="/alerts" className="transition-all hover:shadow-md hover:-translate-y-1">
                            <MetricCard
                                title="Low Stock Items"
                                value={data.lowStockCount.toString()}
                                icon={AlertCircle}
                                variant="warning"
                                label="Items at or below reorder point"
                            />
                        </Link>
                        <Link href="/inventory" className="transition-all hover:shadow-md hover:-translate-y-1">
                            <MetricCard
                                title="Total SKUs"
                                value={data.totalSKUs.toString()}
                                icon={Package}
                                label="Unique products in inventory"
                            />
                        </Link>
                        <Link href="/suppliers" className="transition-all hover:shadow-md hover:-translate-y-1">
                            <MetricCard
                                title="Total Suppliers"
                                value={data.totalSuppliers.toString()}
                                icon={Truck}
                            />
                        </Link>
                    </>
                ) : null}
            </div>
        </div>
    );
}
