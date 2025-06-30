
'use client';

import { AlertTriangle, DollarSign, Package, Users, ShoppingCart, BarChart, TrendingUp, RefreshCw, ArrowUp, ArrowDown, Plus } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { getDashboardData } from '@/app/data-actions';
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
                    stroke="hsl(var(--primary-foreground))"
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
    gradient,
}: {
    title: string;
    value: string;
    icon: React.ElementType;
    trend: string;
    gradient: string;
}) {
    return (
        <motion.div whileHover={{ y: -5, boxShadow: '0 10px 20px -5px hsl(var(--primary)/0.2)' }} className="h-full">
            <Card className={cn("relative overflow-hidden h-full text-primary-foreground", gradient)}>
                <div className="absolute top-0 right-0 -m-4 h-24 w-24 rounded-full bg-white/10" />
                <CardHeader>
                    <div className="flex items-center gap-2">
                        <Icon className="h-5 w-5" />
                        <CardTitle className="text-base font-medium">{title}</CardTitle>
                    </div>
                </CardHeader>
                <CardContent>
                    <div className="text-4xl font-bold">{value}</div>
                    <p className="text-xs text-primary-foreground/80 mt-1">{trend}</p>
                </CardContent>
            </Card>
        </motion.div>
    );
}

function SparklineMetricCard({
    title,
    value,
    icon: Icon,
    sparklineData,
    trendValue,
    trendDirection
}: {
    title: string;
    value: string;
    icon: React.ElementType;
    sparklineData: { value: number }[];
    trendValue: string;
    trendDirection: 'up' | 'down';
}) {
    const TrendIcon = trendDirection === 'up' ? ArrowUp : ArrowDown;
    const trendColor = trendDirection === 'up' ? 'text-success' : 'text-destructive';

    return (
        <Card className="h-full hover:shadow-lg transition-shadow duration-300">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
                <Icon className="h-5 w-5 text-muted-foreground" />
            </CardHeader>
            <CardContent>
                <div className="flex items-end justify-between">
                    <div>
                        <div className="text-3xl font-bold text-foreground">{value}</div>
                        <div className="flex items-center text-xs text-muted-foreground">
                            <TrendIcon className={cn("h-4 w-4 mr-1", trendColor)} />
                            <span className={trendColor}>{trendValue}</span> vs last period
                        </div>
                    </div>
                    <div className="w-24 h-10">
                        <Sparkline data={sparklineData} />
                    </div>
                </div>
            </CardContent>
        </Card>
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
        <div className="space-y-6">
            <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
                <Skeleton className="h-40 rounded-xl" />
                <Skeleton className="h-40 rounded-xl" />
                <Skeleton className="h-40 rounded-xl" />
                <Skeleton className="h-40 rounded-xl" />
            </div>
            <div className="grid grid-cols-1 gap-6 lg:grid-cols-4">
                <Skeleton className="h-96 rounded-xl lg:col-span-4" />
                <Skeleton className="h-96 rounded-xl lg:col-span-3" />
                <Skeleton className="h-96 rounded-xl lg:col-span-1" />
            </div>
        </div>
    )
}

// --- Main Page Component ---
export default function DashboardPage({ searchParams }: { searchParams?: { range?: string } }) {
    const [data, setData] = useState<DashboardMetrics | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<Error | null>(null);
    const dateRange = searchParams?.range || '30d';
    
    useEffect(() => {
        const fetchData = async () => {
            setLoading(true);
            setError(null);
            try {
                const result = await getDashboardData(dateRange);
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
            ) : data ? (
                <div className="space-y-8">
                    {/* Top Row: Gradient Cards and Quick Actions */}
                    <div className="grid grid-cols-1 gap-6 lg:grid-cols-4">
                        <div className="lg:col-span-3">
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-6 h-full">
                                <Link href="/analytics">
                                    <GradientMetricCard
                                        title="Total Revenue"
                                        value={formatCurrency(data.totalSalesValue)}
                                        icon={BarChart}
                                        trend="+12.5% this month"
                                        gradient="bg-gradient-to-br from-primary to-violet-500"
                                    />
                                </Link>
                                <Link href="/analytics">
                                    <GradientMetricCard
                                        title="Total Profit"
                                        value={formatCurrency(data.totalProfit)}
                                        icon={TrendingUp}
                                        trend="+8.2% this month"
                                        gradient="bg-gradient-to-br from-emerald-500 to-green-500"
                                    />
                                </Link>
                            </div>
                        </div>
                        <Card className="lg:col-span-1 p-4 flex flex-col justify-center">
                            <CardTitle className="text-base mb-4">Quick Actions</CardTitle>
                            <div className="space-y-3">
                                <Button asChild className="w-full justify-start" variant="ghost">
                                    <Link href="/analytics"><Plus className="mr-2" /> New Report</Link>
                                </Button>
                                <Button asChild className="w-full justify-start" variant="ghost">
                                    <Link href="/import"><Package className="mr-2" /> Import Products</Link>
                                </Button>
                                <Button asChild className="w-full justify-start" variant="ghost">
                                    <Link href="/settings/team"><Users className="mr-2" /> Invite Team</Link>
                                </Button>
                            </div>
                        </Card>
                    </div>

                    {/* Second Row: Sparkline Metric Cards */}
                    <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
                        <Link href="/analytics">
                            <SparklineMetricCard
                                title="Average Order Value"
                                value={formatCurrency(data.averageOrderValue)}
                                icon={DollarSign}
                                sparklineData={mockSparkline}
                                trendValue="+5.1%"
                                trendDirection="up"
                            />
                        </Link>
                        <Link href="/inventory">
                             <SparklineMetricCard
                                title="Inventory Value"
                                value={formatCurrency(data.totalInventoryValue)}
                                icon={Package}
                                sparklineData={mockSparkline.slice().reverse()}
                                trendValue="-1.2%"
                                trendDirection="down"
                            />
                        </Link>
                         <SparklineMetricCard
                            title="Return Rate"
                            value={`${data.returnRate.toFixed(1)}%`}
                            icon={RefreshCw}
                            sparklineData={mockSparkline}
                            trendValue="-0.5%"
                            trendDirection="down"
                        />
                         <Link href="/reordering">
                            <SparklineMetricCard
                                title="Low Stock SKUs"
                                value={formatNumber(data.lowStockItemsCount)}
                                icon={AlertTriangle}
                                sparklineData={mockSparkline.slice().reverse()}
                                trendValue="+3 items"
                                trendDirection="up"
                            />
                        </Link>
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
