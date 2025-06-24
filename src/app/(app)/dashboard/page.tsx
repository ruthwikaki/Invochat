
import { AlertCircle, Package, TrendingDown, DollarSign, Truck, BarChart } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { cn } from '@/lib/utils';
import { getDashboardData } from '@/app/data-actions';
import { Badge } from '@/components/ui/badge';

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
    <Card className={cn(variantClasses[variant])}>
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

export default async function DashboardPage() {
    let data = {
        inventoryValue: 0,
        deadStockValue: 0,
        onTimeDeliveryRate: 0,
        predictiveAlert: null,
    };

    try {
        data = await getDashboardData();
    } catch (error) {
        console.error("Failed to fetch dashboard metrics:", error);
    }

    return (
        <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <SidebarTrigger className="md:hidden" />
                    <h1 className="text-2xl font-semibold">Dashboard</h1>
                </div>
            </div>

            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                <MetricCard
                    title="Total Inventory Value"
                    value={formatCurrency(data.inventoryValue)}
                    icon={DollarSign}
                    variant="success"
                />
                 <MetricCard
                    title="Dead Stock Value"
                    value={formatCurrency(data.deadStockValue)}
                    icon={TrendingDown}
                    variant="destructive"
                />
                <MetricCard
                    title="On-Time Delivery Rate"
                    value={`${data.onTimeDeliveryRate.toFixed(0)}%`}
                    icon={Truck}
                    variant="default"
                />
                 <Card className="border-warning/50 text-warning">
                    <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                        <CardTitle className="text-sm font-medium">Predictive Alert</CardTitle>
                        <AlertCircle className="h-5 w-5 text-muted-foreground" />
                    </CardHeader>
                    <CardContent>
                        {data.predictiveAlert ? (
                            <>
                                <div className="text-xl font-bold">{data.predictiveAlert.item}</div>
                                <p className="text-xs text-muted-foreground">Predicted to run out in ~{data.predictiveAlert.days} days.</p>
                            </>
                        ) : (
                             <div className="text-xl font-bold text-muted-foreground">All Good!</div>
                        )}
                    </CardContent>
                </Card>
            </div>
        </div>
    );
}
