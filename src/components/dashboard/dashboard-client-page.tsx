
'use client';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Users,
  TrendingDown,
  Wallet,
  ShoppingCart
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
import type { DashboardMetrics } from '@/types';
import { motion } from 'framer-motion';
import { cn } from '@/lib/utils';
import { formatCentsAsCurrency } from '@/lib/utils';
import { QuickActions } from '@/components/dashboard/quick-actions';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { createBrowserClient } from '@supabase/ssr';
import { getDashboardData } from '@/app/data-actions';
import { Skeleton } from '../ui/skeleton';

interface DashboardClientPageProps {
    initialMetrics: DashboardMetrics;
    initialBriefing: {
        greeting: string;
        summary: string;
        cta?: { text: string; link: string };
    };
}

const StatCard = ({ title, value, change, icon: Icon, changeType, gradient }: { title: string; value: string; change?: string; icon: React.ElementType; changeType?: 'increase' | 'decrease' | 'neutral', gradient: string }) => {
    const changeColor = changeType === 'increase' ? 'text-success' : changeType === 'decrease' ? 'text-destructive' : 'text-muted-foreground';
    
    return (
        <Card className="relative overflow-hidden border-border/50 bg-card/80 backdrop-blur-sm">
            <div className={cn("absolute -top-1/4 -right-1/4 w-1/2 h-1/2 rounded-full opacity-10 blur-3xl", gradient)}></div>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">{title}</CardTitle>
                <Icon className="h-5 w-5 text-muted-foreground" />
            </CardHeader>
            <CardContent>
                <div className="text-3xl font-bold font-tabular">{value}</div>
                {change && (
                    <p className={cn("text-xs font-tabular", changeColor)}>
                        {change} from last period
                    </p>
                )}
            </CardContent>
        </Card>
    );
};

export function DashboardClientPage({ initialMetrics, initialBriefing }: DashboardClientPageProps) {
    const router = useRouter();
    const [metrics, setMetrics] = useState(initialMetrics);
    const [loading, setLoading] = useState(false);

    const handleDateChange = (value: string) => {
        setLoading(true);
        router.push(`/dashboard?range=${value}`);
        getDashboardData(value).then(data => {
            setMetrics(data);
            setLoading(false);
        });
    };
    
    if (loading) {
      return (
        <div className="space-y-6">
          <div className="flex flex-col md:flex-row items-start justify-between gap-4">
              <Skeleton className="h-8 w-48" />
              <Skeleton className="h-10 w-[180px]" />
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <Skeleton className="h-24"/>
            <Skeleton className="h-24"/>
            <Skeleton className="h-24"/>
            <Skeleton className="h-24"/>
          </div>
          <Skeleton className="h-48" />
           <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
             <Skeleton className="h-28"/>
             <Skeleton className="h-28"/>
             <Skeleton className="h-28"/>
             <Skeleton className="h-28"/>
           </div>
        </div>
      )
    }

    return (
        <motion.div 
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="space-y-6"
        >
            <div className="flex flex-col md:flex-row items-start justify-between gap-4">
                <div>
                    {/* The title and description are now in the server component */}
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
            
            <QuickActions />

            <MorningBriefingCard briefing={initialBriefing} />

            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                <StatCard title="Total Revenue" value={formatCentsAsCurrency(metrics.total_revenue)} change={`${metrics.revenue_change.toFixed(1)}%`} icon={Wallet} changeType={metrics.revenue_change >= 0 ? 'increase' : 'decrease'} gradient="bg-emerald-500" />
                <StatCard title="Total Sales" value={metrics.total_sales.toLocaleString()} change={`${metrics.sales_change.toFixed(1)}%`} icon={ShoppingCart} changeType={metrics.sales_change >= 0 ? 'increase' : 'decrease'} gradient="bg-sky-500" />
                <StatCard title="New Customers" value={metrics.new_customers.toLocaleString()} change={`${metrics.customers_change.toFixed(1)}%`} icon={Users} changeType={metrics.customers_change >= 0 ? 'increase' : 'decrease'} gradient="bg-violet-500" />
                <StatCard title="Dead Stock Value" value={formatCentsAsCurrency(metrics.dead_stock_value)} icon={TrendingDown} gradient="bg-rose-500" />
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <SalesChart data={metrics.sales_over_time} />
                <TopProductsCard data={metrics.top_selling_products} />
            </div>
            
            <InventorySummaryCard data={metrics.inventory_summary} />
        </motion.div>
    );
}

    