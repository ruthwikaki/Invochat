'use client';

import {
  AlertCircle,
  Package,
  TrendingDown,
  Truck
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { useState, useEffect } from 'react';
import { Skeleton } from '@/components/ui/skeleton';
import { ReorderModal } from '@/components/reorder-modal';
import { InventoryValueChart } from '@/components/charts/inventory-value-chart';
import { InventoryTrendChart } from '@/components/charts/inventory-trend-chart';
import { formatDistanceToNow } from 'date-fns';

function MetricCard({ title, value, icon: Icon, className, label, loading }: { title: string; value: string; icon: React.ElementType; className?: string; label?: string; loading: boolean }) {
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
  return (
    <Card className={className}>
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
    const [loading, setLoading] = useState(true);
    const [isReorderModalOpen, setReorderModalOpen] = useState(false);
    const [alertTime, setAlertTime] = useState('');

    useEffect(() => {
        const timer = setTimeout(() => setLoading(false), 1500);
        
        const alertDate = new Date();
        alertDate.setDate(alertDate.getDate() + 7);
        
        const updateAlertTime = () => {
          setAlertTime(formatDistanceToNow(alertDate, { addSuffix: true }));
        }
        
        updateAlertTime();
        const interval = setInterval(updateAlertTime, 60000);

        return () => {
            clearTimeout(timer);
            clearInterval(interval);
        }
    }, []);

    return (
        <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <SidebarTrigger className="md:hidden" />
                    <h1 className="text-2xl font-semibold">Dashboard</h1>
                </div>
            </div>

            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                <Card className="col-span-1 lg:col-span-2">
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2 text-amber-400">
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
                        ) : (
                            <>
                                <p className="text-sm">
                                    You will run out of{' '}
                                    <span className="font-semibold text-primary-foreground">
                                        XYZ Cleaner
                                    </span>{' '}
                                    <span className="font-semibold text-amber-400">{alertTime}</span>.
                                </p>
                                <Button size="sm" className="mt-2" onClick={() => setReorderModalOpen(true)}>
                                    Reorder Now
                                </Button>
                            </>
                        )}
                    </CardContent>
                </Card>
                <MetricCard
                    title="Inventory Value"
                    value="$1.2M"
                    icon={Package}
                    label="+5.2% this month"
                    loading={loading}
                />
                <MetricCard
                    title="Dead Stock"
                    value="$12.4k"
                    icon={TrendingDown}
                    className="border-destructive/50 text-destructive"
                    label="-2.1% this month"
                    loading={loading}
                />
                <MetricCard
                    title="On-Time Deliveries"
                    value="98.2%"
                    icon={Truck}
                    className="border-emerald-500/50 text-emerald-500"
                    label="+1.5% this month"
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
            <ReorderModal open={isReorderModalOpen} onOpenChange={setReorderModalOpen} />
        </div>
    );
}
