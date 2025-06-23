'use client';

import { AlertCircle, Package, TrendingDown, Truck } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { useState, useEffect } from 'react';
import { Skeleton } from '@/components/ui/skeleton';
import { ReorderModal } from '@/components/reorder-modal';
import { InventoryValueChart } from '@/components/charts/inventory-value-chart';
import { InventoryTrendChart } from '@/components/charts/inventory-trend-chart';
import { cn } from '@/lib/utils';
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';
import { getDashboardData } from '@/app/data-actions';
import type { DashboardMetrics } from '@/types';

function formatCurrency(value: number) {
    if (Math.abs(value) >= 1_000_000) {
        return `$${(value / 1_000_000).toFixed(1)}M`;
    }
    if (Math.abs(value) >= 1_000) {
        return `$${(value / 1_000).toFixed(1)}k`;
    }
    return `$${value.toFixed(0)}`;
}


function MetricCard({ title, value, icon: Icon, variant = 'default', label, loading }: { title: string; value: string; icon: React.ElementType; variant?: 'default' | 'destructive' | 'success'; label?: string; loading: boolean }) {
  if (loading) {
    return (
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <Skeleton className="h-4 w-2/4" />
          <Skeleton className="h-5 w-5 rounded-full" />
        </CardHeader>
        <CardContent>
          <Skeleton className="h-7 w-1/3" />
          <Skeleton className="h-3 w-3/4 mt-1" />
        </CardContent>
      </Card>
    )
  }
  
  const variantClasses = {
      default: '',
      destructive: 'border-destructive/50 text-destructive',
      success: 'border-success/50 text-success'
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

export default function DashboardPage() {
    const [data, setData] = useState<DashboardMetrics | null>(null);
    const [loading, setLoading] = useState(true);
    const [isReorderModalOpen, setReorderModalOpen] = useState(false);
    const { user, getIdToken } = useAuth();
    const { toast } = useToast();

    useEffect(() => {
        if (user) {
            const fetchData = async () => {
                setLoading(true);
                try {
                    const token = await getIdToken();
                    if (!token) throw new Error("Authentication failed");
                    const result = await getDashboardData(token);
                    setData(result);
                } catch (error) {
                    console.error("Failed to fetch dashboard metrics:", error);
                    toast({
                        variant: 'destructive',
                        title: 'Error',
                        description: 'Could not load dashboard data.'
                    });
                } finally {
                    setLoading(false);
                }
            };
            fetchData();
        }
    }, [user, getIdToken, toast]);

    return (
        <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <SidebarTrigger className="md:hidden" />
                    <h1 className="text-2xl font-semibold">Dashboard</h1>
                </div>
            </div>

            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                <Card className="col-span-1 lg:col-span-2 border-warning/50">
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2 text-warning">
                            <AlertCircle className="h-5 w-5" />
                            Predictive Alerts
                        </CardTitle>
                    </CardHeader>
                    <CardContent>
                        {loading ? (
                            <div className="space-y-2">
                                <Skeleton className="h-4 w-3/4" />
                                <Skeleton className="h-9 w-24" />
                            </div>
                        ) : data?.predictiveAlert ? (
                            <>
                                <p className="text-sm">
                                    You will run out of{' '}
                                    <span className="font-semibold text-foreground">
                                        {data.predictiveAlert.item}
                                    </span>{' '}
                                    in about{' '}
                                    <span className="font-semibold text-warning">{data.predictiveAlert.days} days</span>.
                                </p>
                                <Button size="sm" className="mt-2" onClick={() => setReorderModalOpen(true)}>
                                    Reorder Now
                                </Button>
                            </>
                        ) : (
                           <p className="text-sm text-muted-foreground">No immediate stock-out risks detected.</p>
                        )}
                    </CardContent>
                </Card>
                <MetricCard
                    title="Inventory Value"
                    value={data ? formatCurrency(data.inventoryValue) : '...'}
                    icon={Package}
                    loading={loading}
                />
                <MetricCard
                    title="Dead Stock"
                    value={data ? formatCurrency(data.deadStockValue) : '...'}
                    icon={TrendingDown}
                    variant="destructive"
                    loading={loading}
                />
                <MetricCard
                    title="On-Time Deliveries"
                    value={data ? `${data.onTimeDeliveryRate.toFixed(1)}%` : '...'}
                    icon={Truck}
                    variant="success"
                    loading={loading}
                />
                
                {loading ? (
                    <Card className="col-span-1 lg:col-span-3">
                        <CardHeader>
                            <Skeleton className="h-6 w-1/3" />
                        </CardHeader>
                        <CardContent>
                            <Skeleton className="h-48 w-full" />
                        </CardContent>
                    </Card>
                ) : (
                    <InventoryTrendChart />
                )}
                
                {loading ? (
                    <Card className="col-span-1 md:col-span-2 lg:col-span-4">
                        <CardHeader>
                             <Skeleton className="h-6 w-1/4" />
                        </CardHeader>
                        <CardContent>
                            <Skeleton className="h-[300px] w-full" />
                        </CardContent>
                    </Card>
                ) : (
                    <div className="col-span-1 md:col-span-2 lg:col-span-4">
                        <InventoryValueChart />
                    </div>
                )}
            </div>
            <ReorderModal item={data?.predictiveAlert?.item} open={isReorderModalOpen} onOpenChange={setReorderModalOpen} />
        </div>
    );
}
