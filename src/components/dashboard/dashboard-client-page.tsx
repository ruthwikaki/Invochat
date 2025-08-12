

'use client';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Users,
  TrendingDown,
  Wallet,
  ShoppingCart,
  Package,
  Sparkles,
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
import type { DashboardMetrics, CompanySettings } from '@/types';
import { motion } from 'framer-motion';
import { cn } from '@/lib/utils';
import { formatCentsAsCurrency } from '@/lib/utils';
import { QuickActions } from '@/components/dashboard/quick-actions';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import Link from 'next/link';

interface DashboardClientPageProps {
    initialMetrics: DashboardMetrics;
    settings: CompanySettings;
    initialBriefing: {
        greeting: string;
        summary: string;
        cta?: { text: string; link: string };
    };
}

function EmptyDashboardState() {
  return (
    <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
        className="relative bg-primary/10 rounded-full p-6"
      >
        <Package className="h-16 w-16 text-primary" />
        <motion.div
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.4, duration: 0.5 }}
          className="absolute -top-2 -right-2 text-primary"
        >
          <Sparkles className="h-8 w-8" />
        </motion.div>
      </motion.div>
      <h3 className="mt-6 text-xl font-semibold">Welcome to ARVO!</h3>
      <p className="mt-2 text-muted-foreground">
        Your dashboard is ready. Import your data to see your metrics and get AI insights.
      </p>
      <Button asChild className="mt-6">
        <Link href="/import">Import Your First Data Set</Link>
      </Button>
    </Card>
  );
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

export function DashboardClientPage({ initialMetrics, settings, initialBriefing }: DashboardClientPageProps) {
    const router = useRouter();

    const handleDateChange = (value: string) => {
        router.push(`/dashboard?range=${value}`);
    };
    
    const hasData = initialMetrics && (
        initialMetrics.total_revenue > 0 ||
        initialMetrics.total_orders > 0 ||
        (initialMetrics.inventory_summary && initialMetrics.inventory_summary.total_value > 0)
    );

    if (!hasData) {
        return (
            <div className="space-y-6">
                 <QuickActions />
                 <EmptyDashboardState />
            </div>
        )
    }

    return (
        <motion.div 
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="space-y-6"
            data-testid="dashboard-root"
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
                <StatCard title="Total Revenue" value={formatCentsAsCurrency(initialMetrics.total_revenue, settings.currency)} change={`${initialMetrics.revenue_change.toFixed(1)}%`} icon={Wallet} changeType={initialMetrics.revenue_change >= 0 ? 'increase' : 'decrease'} gradient="bg-emerald-500" />
                <StatCard title="Total Orders" value={initialMetrics.total_orders.toLocaleString()} change={`${initialMetrics.orders_change.toFixed(1)}%`} icon={ShoppingCart} changeType={initialMetrics.orders_change >= 0 ? 'increase' : 'decrease'} gradient="bg-sky-500" />
                <StatCard title="New Customers" value={initialMetrics.new_customers.toLocaleString()} change={`${initialMetrics.customers_change.toFixed(1)}%`} icon={Users} changeType={initialMetrics.customers_change >= 0 ? 'increase' : 'decrease'} gradient="bg-violet-500" />
                <StatCard title="Dead Stock Value" value={formatCentsAsCurrency(initialMetrics.dead_stock_value, settings.currency)} icon={TrendingDown} gradient="bg-rose-500" />
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <SalesChart data={initialMetrics.sales_over_time} currency={settings.currency} />
                <TopProductsCard data={initialMetrics.top_products} currency={settings.currency} />
            </div>
            
            <InventorySummaryCard data={initialMetrics.inventory_summary} currency={settings.currency} />
        </motion.div>
    );
}
