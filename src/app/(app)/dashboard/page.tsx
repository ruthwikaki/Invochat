

'use client';

import { AlertTriangle, DollarSign, Package, Users, ShoppingCart, BarChart, TrendingUp, RefreshCw, ArrowUp, ArrowDown, Plus } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { getDashboardData, getMorningBriefing } from '@/app/data-actions';
import Link from 'next/link';
import { SalesTrendChart } from '@/components/dashboard/sales-trend-chart';
import { InventoryCategoryChart } from '@/components/dashboard/inventory-category-chart';
import { TopCustomersChart } from '@/components/dashboard/top-customers-chart';
import { DashboardHeaderControls } from '@/components/dashboard/header-controls';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { motion } from 'framer-motion';
import { ResponsiveContainer, LineChart, Line } from 'recharts';
import { Button } from '@/components/ui/button';
import { useEffect, useState } from 'react';
import type { DashboardMetrics } from '@/types';
import { Skeleton } from '@/components/ui/skeleton';
import { BusinessHealthScore } from '@/components/dashboard/business-health-score';
import { RoiCounter } from '@/components/dashboard/roi-counter';
import { DashboardEmptyState } from '@/components/dashboard/dashboard-empty-state';
import { MorningBriefing } from '@/components/dashboard/morning-briefing';


// --- Data Formatting Utilities ---
function formatCurrency(value: number) {
    if (Math.abs(value) >= 1_000_000) return `$${(value / 1_000_000).toFixed(1)}M`;
    if (Math.abs(value) >= 1_000) return `$${(value / 1_000).toFixed(1)}k`;
    return `$${value.toFixed(2)}`;
}

function formatNumber(value: number) {
    if (Math.abs(value) >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
    if (Math.abs(value) >= 1_000) return `${(value / 1_000).toFixed(1)}k`;
    return value.toString();
}

// --- Page-Specific Components ---
function Sparkline({ data }: { data: { value: number }[] }) {
    return (
        <ResponsiveContainer width="100%" height={40}>
            <LineChart data={data}>
                <Line
                    type="natural"
                    dataKey="value"
                    stroke={'hsl(var(--primary-foreground))'}
                    strokeWidth={2}
                    dot={false}
                    isAnimationActive={false}
                />
            </LineChart>
        </ResponsiveContainer>
    );
}

function GradientMetricCard({
    title,
    value,
    icon: Icon,
    trend,
    trendDirection,
    sparklineData,
    gradient,
}: {
    title: string;
    value: string;
    icon: React.ElementType;
    trend: string;
    trendDirection: 'up' | 'down' | 'neutral';
    sparklineData: { value: number }[];
    gradient: string;
}) {
    const TrendIcon = trendDirection === 'up' ? ArrowUp : ArrowDown;
    
    return (
        <motion.div whileHover={{ y: -5, boxShadow: '0 10px 20px -5px hsl(var(--primary)/0.2)' }} className="h-full">
            <Card className={cn("relative overflow-hidden h-full text-primary-foreground", gradient)}>
                <div className="absolute top-0 right-0 -m-4 h-24 w-24 rounded-full bg-white/10" />
                <CardHeader>
                    <div className="flex items-center justify-between">
                         <div className="flex items-center gap-2">
                            <Icon className="h-5 w-5" />
                            <CardTitle className="text-base font-medium">{title}</CardTitle>
                        </div>
                         <div className="flex items-center text-xs font-semibold text-primary-foreground/80">
                            {trendDirection !== 'neutral' && <TrendIcon className="h-4 w-4 mr-1" />}
                            {trend}
                        </div>
                    </div>
                </CardHeader>
                <CardContent className="flex items-end justify-between">
                    <div className="text-4xl font-bold">{value}</div>
                    <div className="w-24 h-10">
                       <Sparkline data={sparklineData} />
                    </div>
                </CardContent>
            </Card>
        </motion.div>
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
                    There was an issue fetching the dashboard metrics.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <p className="text-sm font-mono bg-destructive/20 p-2 rounded-md">{error.message}</p>
            </CardContent>
        </Card>
    );
}

function DashboardSkeleton() {
    return (
        <div className="space-y-8">
            <Skeleton className="h-32 w-full" />
            {/* Top Row: Value-add Widgets */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <Card className="h-[230px]">
                    <CardHeader>
                        <Skeleton className="h-5 w-1/2" />
                        <Skeleton className="h-4 w-3/4 mt-1" />
                    </CardHeader>
                    <CardContent className="flex items-center justify-center h-full -mt-12">
                        <Skeleton className="h-24 w-24 rounded-full" />
                    </CardContent>
                </Card>
                <Card className="h-[230px]">
                    <CardHeader>
                        <Skeleton className="h-5 w-1/2" />
                        <Skeleton className="h-4 w-3/4 mt-1" />
                    </CardHeader>
                    <CardContent className="flex items-center justify-center h-full -mt-12">
                        <Skeleton className="h-24 w-24 rounded-full" />
                    </CardContent>
                </Card>
            </div>

            {/* Second Row: Core Metric Cards */}
            <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
                {Array.from({ length: 4 }).map((_, i) => (
                    <Card key={i} className="h-[160px]">
                        <CardHeader>
                            <Skeleton className="h-4 w-2/3" />
                        </CardHeader>
                        <CardContent>
                            <Skeleton className="h-10 w-1/2 mb-4" />
                            <Skeleton className="h-3 w-1/3" />
                        </CardContent>
                    </Card>
                ))}
            </div>

            {/* Bottom Row: Main Charts */}
            <div className="grid grid-cols-1 gap-6 lg:grid-cols-4">
                <Card className="lg:col-span-4 h-96">
                    <CardHeader><Skeleton className="h-5 w-1/4" /><Skeleton className="h-4 w-1/2 mt-1" /></CardHeader>
                    <CardContent><Skeleton className="h-64 w-full" /></CardContent>
                </Card>
                <Card className="lg:col-span-3 h-96">
                    <CardHeader><Skeleton className="h-5 w-1/4" /><Skeleton className="h-4 w-1/2 mt-1" /></CardHeader>
                    <CardContent><Skeleton className="h-64 w-full" /></CardContent>
                </Card>
                <Card className="lg:col-span-1 h-96">
                    <CardHeader><Skeleton className="h-5 w-1/4" /><Skeleton className="h-4 w-1/2 mt-1" /></CardHeader>
                    <CardContent><Skeleton className="h-64 w-full" /></CardContent>
                </Card>
            </div>
        </div>
    );
}

// --- Main Page Component ---
export default function DashboardPage({ searchParams }: { searchParams?: { range?: string } }) {
    const [data, setData] = useState<DashboardMetrics | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<Error | null>(null);
    const [isEmpty, setIsEmpty] = useState(false);
    const dateRange = searchParams?.range || '30d';
    
    useEffect(() => {
        const fetchData = async () => {
            setLoading(true);
            setError(null);
            setIsEmpty(false);
            try {
                const result = await getDashboardData(dateRange);
                // If there are no products and no sales, it's a new account.
                if (result.totalSkus === 0 && result.totalOrders === 0) {
                    setIsEmpty(true);
                }
                setData(result);
            } catch (e) {
                setError(e as Error);
            } finally {
                setLoading(false);
            }
        };
        fetchData();
    }, [dateRange]);
    
    // Mock sparkline data for UI demonstration
    const mockSparkline = Array.from({ length: 20 }, () => ({ value: Math.random() * 100 }));

    return (
        <AppPage>
            <AppPageHeader title="Dashboard">
                <DashboardHeaderControls />
            </AppPageHeader>

            {loading ? (
                <DashboardSkeleton />
            ) : error ? (
                <ErrorDisplay error={error} />
            ) : isEmpty ? (
                <DashboardEmptyState />
            ) : data ? (
                <div className="space-y-8">
                    <MorningBriefing dateRange={dateRange} />
                    {/* Top Row: Value-add Widgets */}
                     <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                        <RoiCounter metrics={data} />
                        <BusinessHealthScore metrics={data} />
                    </div>

                    {/* Second Row: Core Metric Cards */}
                    <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
                        <GradientMetricCard
                            title="Total Revenue"
                            value={formatCurrency(data.totalSalesValue)}
                            icon={BarChart}
                            trend="+12.5%"
                            trendDirection="up"
                            sparklineData={mockSparkline}
                            gradient="bg-gradient-to-br from-primary to-violet-500"
                        />
                         <GradientMetricCard
                            title="Total Profit"
                            value={formatCurrency(data.totalProfit)}
                            icon={TrendingUp}
                            trend="+8.2%"
                            trendDirection="up"
                            sparklineData={mockSparkline}
                            gradient="bg-gradient-to-br from-emerald-500 to-green-500"
                        />
                        <GradientMetricCard
                            title="Average Order Value"
                            value={formatCurrency(data.averageOrderValue)}
                            icon={DollarSign}
                            trend="-1.2%"
                            trendDirection="down"
                            sparklineData={mockSparkline.slice().reverse()}
                            gradient="bg-gradient-to-br from-sky-500 to-blue-500"
                        />
                        <GradientMetricCard
                            title="Inventory Value"
                            value={formatCurrency(data.totalInventoryValue)}
                            icon={Package}
                            trend="Stable"
                            trendDirection="neutral"
                            sparklineData={mockSparkline}
                            gradient="bg-gradient-to-br from-slate-600 to-gray-800"
                        />
                    </div>

                    {/* Bottom Row: Main Charts */}
                    <div className="grid grid-cols-1 gap-6 lg:grid-cols-4">
                        <SalesTrendChart data={data.salesTrendData} className="lg:col-span-4" />
                        <TopCustomersChart data={data.topCustomersData} className="lg:col-span-3" />
                        <InventoryCategoryChart data={data.inventoryByCategoryData} className="lg:col-span-1" />
                    </div>
                </div>
            ) : null}
        </AppPage>
    );
}
