
'use client';

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  CardFooter,
} from '@/components/ui/card';
import { getInsightsPageData } from '@/app/data-actions';
import { Lightbulb, AlertTriangle, CheckCircle, Bot, TrendingDown, Package, FileText, ArrowRight } from 'lucide-react';
import { useState, useEffect } from 'react';
import { Skeleton } from '@/components/ui/skeleton';
import { useToast } from '@/hooks/use-toast';
import { getErrorMessage } from '@/lib/error-handler';
import type { Anomaly, DeadStockItem, Alert } from '@/types';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Button } from '@/components/ui/button';
import Link from 'next/link';

interface InsightsData {
    summary: string;
    anomalies: Anomaly[];
    topDeadStock: DeadStockItem[];
    topLowStock: Alert[];
}

function AnomalyCard({ anomaly }: { anomaly: Anomaly }) {
  const isRevenue = anomaly.anomaly_type === 'Revenue Anomaly';
  const currentValue = isRevenue ? anomaly.daily_revenue : anomaly.daily_customers;
  const averageValue = isRevenue ? anomaly.avg_revenue : anomaly.avg_customers;
  const deviation = Math.abs(currentValue - averageValue);
  const direction = currentValue > averageValue ? 'higher' : 'lower';
  
  return (
    <div className="border-t p-4">
      <h4 className="font-semibold text-warning flex items-center gap-2">
        <AlertTriangle className="h-4 w-4" />
        {anomaly.anomaly_type} on {new Date(anomaly.date).toLocaleDateString()}
      </h4>
      <p className="text-sm text-muted-foreground mt-1">
        Detected significant deviation. The {isRevenue ? 'daily revenue' : 'customer count'} was{' '}
        <strong className="text-foreground">{isRevenue ? `$${Number(currentValue).toLocaleString()}` : currentValue}</strong>, which is{' '}
        {averageValue > 0 ? ((deviation / averageValue) * 100).toFixed(0) : '100'}% {direction} than the average.
      </p>
    </div>
  );
}

function LoadingSkeleton() {
    return (
        <div className="space-y-6">
            <Card>
                <CardHeader>
                    <Skeleton className="h-6 w-1/3" />
                    <Skeleton className="h-4 w-2/3" />
                </CardHeader>
                <CardContent>
                    <Skeleton className="h-16 w-full" />
                </CardContent>
            </Card>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <Card>
                    <CardHeader><Skeleton className="h-6 w-1/2" /></CardHeader>
                    <CardContent><Skeleton className="h-24 w-full" /></CardContent>
                </Card>
                <Card>
                    <CardHeader><Skeleton className="h-6 w-1/2" /></CardHeader>
                    <CardContent><Skeleton className="h-24 w-full" /></CardContent>
                </Card>
                 <Card className="lg:col-span-2">
                    <CardHeader><Skeleton className="h-6 w-1/2" /></CardHeader>
                    <CardContent><Skeleton className="h-24 w-full" /></CardContent>
                </Card>
            </div>
        </div>
    )
}

export default function InsightsPage() {
  const [insights, setInsights] = useState<InsightsData | null>(null);
  const [loading, setLoading] = useState(true);
  const { toast } = useToast();

  useEffect(() => {
    async function fetchInsights() {
      try {
        setLoading(true);
        const data = await getInsightsPageData();
        setInsights(data);
      } catch (error) {
        toast({
          variant: 'destructive',
          title: 'Error Fetching Insights',
          description: getErrorMessage(error) || 'Could not load insights data.'
        });
      } finally {
        setLoading(false);
      }
    }
    fetchInsights();
  }, [toast]);
  
  if (loading) {
    return (
        <AppPage>
            <AppPageHeader
                title="Proactive Insights"
                description="The engine is analyzing your recent data for significant events..."
            />
            <LoadingSkeleton />
        </AppPage>
    )
  }

  return (
    <AppPage>
      <AppPageHeader
        title="Proactive Insights"
        description="The engine automatically scans your recent data for significant events or deviations from normal patterns."
      />
      
      {/* AI Summary Card */}
      <Card className="bg-gradient-to-br from-primary/10 to-primary/5 border-primary/20">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Bot className="h-5 w-5 text-primary" />
            AI Business Summary
          </CardTitle>
          <CardDescription>
            A high-level overview of what's happening in your business right now.
          </CardDescription>
        </CardHeader>
        <CardContent>
            <p className="text-foreground/90">{insights?.summary || "No new insights to summarize at this time."}</p>
        </CardContent>
      </Card>
      
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Dead Stock Insights */}
        <Card>
            <CardHeader>
                <CardTitle className="flex items-center gap-2">
                    <TrendingDown className="h-5 w-5 text-destructive" />
                    Top Dead Stock
                </CardTitle>
                 <CardDescription>
                    Your most valuable items that have not sold recently.
                </CardDescription>
            </CardHeader>
            <CardContent className="p-0">
                {insights?.topDeadStock && insights.topDeadStock.length > 0 ? (
                    insights.topDeadStock.map(item => (
                        <div key={item.sku} className="border-t p-4 flex justify-between items-center">
                            <div>
                                <p className="font-semibold">{item.product_name}</p>
                                <p className="text-sm text-muted-foreground">${item.total_value.toLocaleString(undefined, { maximumFractionDigits: 0 })} in tied-up capital</p>
                            </div>
                             <Button asChild variant="ghost" size="sm">
                                <Link href={`/chat?q=${encodeURIComponent(`Create a promotion plan for ${item.product_name}`)}`}>Ask AI for Plan <ArrowRight className="ml-2 h-4 w-4" /></Link>
                            </Button>
                        </div>
                    ))
                ) : (
                    <p className="p-4 text-sm text-muted-foreground text-center">No significant dead stock to report. Great job!</p>
                )}
            </CardContent>
            <CardFooter className="bg-muted/50 p-3">
                 <Button asChild variant="link" size="sm">
                    <Link href="/dead-stock">View Full Dead Stock Report <ArrowRight className="ml-2 h-4 w-4" /></Link>
                </Button>
            </CardFooter>
        </Card>

        {/* Low Stock Insights */}
        <Card>
            <CardHeader>
                <CardTitle className="flex items-center gap-2">
                    <Package className="h-5 w-5 text-amber-500" />
                    Critical Low Stock
                </CardTitle>
                 <CardDescription>
                    These items have fallen below their reorder point.
                </CardDescription>
            </CardHeader>
            <CardContent className="p-0">
                {insights?.topLowStock && insights.topLowStock.length > 0 ? (
                    insights.topLowStock.map(item => (
                        <div key={item.id} className="border-t p-4 flex justify-between items-center">
                            <div>
                                <p className="font-semibold">{item.metadata.productName}</p>
                                <p className="text-sm text-muted-foreground">
                                    {item.metadata.currentStock} units left (Reorder at {item.metadata.reorderPoint})
                                </p>
                            </div>
                             <Button asChild variant="ghost" size="sm">
                                <Link href={`/inventory?query=${item.metadata.productId}`}>View & Reorder <ArrowRight className="ml-2 h-4 w-4" /></Link>
                            </Button>
                        </div>
                    ))
                ) : (
                    <p className="p-4 text-sm text-muted-foreground text-center">No items are currently below their reorder point.</p>
                )}
            </CardContent>
             <CardFooter className="bg-muted/50 p-3">
                 <Button asChild variant="link" size="sm">
                    <Link href="/reordering">View All Suggestions <ArrowRight className="ml-2 h-4 w-4" /></Link>
                </Button>
            </CardFooter>
        </Card>

         {/* Anomaly Detection */}
        <Card className="lg:col-span-2">
            <CardHeader>
                <CardTitle className="flex items-center gap-2">
                    <Lightbulb className="h-5 w-5 text-primary" />
                    Recent Activity Anomalies
                </CardTitle>
                <CardDescription>
                    Significant deviations from your business's 30-day average activity.
                </CardDescription>
            </CardHeader>
            <CardContent className="p-0">
            {insights?.anomalies.length === 0 ? (
                <div className="h-40 flex flex-col items-center justify-center text-center rounded-lg">
                <CheckCircle className="h-12 w-12 text-muted-foreground" />
                <h3 className="mt-4 text-lg font-semibold">No Anomalies Found</h3>
                <p className="text-muted-foreground">Your recent business activity appears to be within normal parameters.</p>
                </div>
            ) : (
                insights?.anomalies.map((anomaly, index) => (
                    <AnomalyCard key={index} anomaly={anomaly} />
                ))
            )}
            </CardContent>
        </Card>
      </div>

    </AppPage>
  );
}
