
'use client';

import { useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import {
  DollarSign,
  ShoppingCart,
  Users,
  TrendingDown,
  ArrowUpRight,
  Lightbulb,
  BarChart,
  RefreshCw,
} from 'lucide-react';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { SalesChart } from '@/components/dashboard/sales-chart';
import { TopProductsCard } from '@/components/dashboard/top-products-card';
import { InventorySummaryCard } from '@/components/dashboard/inventory-summary-card';
import { MorningBriefingCard } from '@/components/dashboard/morning-briefing-card';
import { getDashboardData } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import type { DashboardMetrics } from '@/types';
import Link from 'next/link';

interface DashboardClientPageProps {
    initialMetrics: DashboardMetrics;
    initialBriefing: {
        greeting: string;
        summary: string;
        cta?: { text: string; link: string };
    };
}

const StatCard = ({ title, value, change, icon: Icon, changeType }: { title: string; value: string; change?: string; icon: React.ElementType; changeType?: 'increase' | 'decrease' | 'neutral' }) => {
    const changeColor = changeType === 'increase' ? 'text-success' : changeType === 'decrease' ? 'text-destructive' : 'text-muted-foreground';
    return (
        <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">{title}</CardTitle>
                <Icon className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
                <div className="text-2xl font-bold">{value}</div>
                {change && (
                    <p className={`text-xs ${changeColor}`}>
                        {change} from last period
                    </p>
                )}
            </CardContent>
        </Card>
    );
};

export function DashboardClientPage({ initialMetrics, initialBriefing }: DashboardClientPageProps) {
    const [metrics, setMetrics] = useState(initialMetrics);
    const [briefing, setBriefing] = useState(initialBriefing);
    const { toast } = useToast();

    const handleDateChange = async (value: string) => {
        try {
            const newMetrics = await getDashboardData(value);
            setMetrics(newMetrics);
            toast({ title: 'Dashboard updated', description: `Showing data for the last ${value.replace('d', '')} days.` });
        } catch (error) {
            toast({ variant: 'destructive', title: 'Error', description: 'Could not fetch new dashboard data.' });
        }
    };
    
    return (
        <div className="space-y-6">
            <div className="flex flex-col md:flex-row items-start justify-between gap-4">
                <div>
                    <h1 className="text-2xl font-semibold tracking-tight">Dashboard</h1>
                    <p className="text-sm text-muted-foreground">
                        Here's a high-level overview of your business performance.
                    </p>
                </div>
                <Select onValueChange={handleDateChange} defaultValue="90d">
                    <SelectTrigger className="w-[180px]">
                        <SelectValue placeholder="Select date range" />
                    </SelectTrigger>
                    <SelectContent>
                        <SelectItem value="7d">Last 7 Days</SelectItem>
                        <SelectItem value="30d">Last 30 Days</SelectItem>
                        <SelectItem value="90d">Last 90 Days</SelectItem>
                    </SelectContent>
                </Select>
            </div>
            
            <MorningBriefingCard briefing={briefing} />

            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                <StatCard title="Total Revenue" value={`$${metrics.total_revenue.toLocaleString()}`} change={`${metrics.revenue_change.toFixed(1)}%`} icon={DollarSign} changeType={metrics.revenue_change >= 0 ? 'increase' : 'decrease'} />
                <StatCard title="Total Sales" value={metrics.total_sales.toLocaleString()} change={`${metrics.sales_change.toFixed(1)}%`} icon={ShoppingCart} changeType={metrics.sales_change >= 0 ? 'increase' : 'decrease'} />
                <StatCard title="New Customers" value={metrics.new_customers.toLocaleString()} change={`${metrics.customers_change.toFixed(1)}%`} icon={Users} changeType={metrics.customers_change >= 0 ? 'increase' : 'decrease'} />
                <StatCard title="Dead Stock Value" value={`$${metrics.dead_stock_value.toLocaleString()}`} icon={TrendingDown} />
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <SalesChart data={metrics.sales_over_time} />
                <TopProductsCard data={metrics.top_selling_products} />
            </div>
            
            <InventorySummaryCard data={metrics.inventory_summary} />
        </div>
    );
}
