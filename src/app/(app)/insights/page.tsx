
'use client';

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  CardFooter,
} from '@/components/ui/card';
import { getInsightsPageData, logUserFeedback } from '@/app/data-actions';
import { Lightbulb, AlertTriangle, CheckCircle, Bot, TrendingDown, Package, ArrowRight, ServerCrash, BrainCircuit, ThumbsUp, ThumbsDown } from 'lucide-react';
import { useState, useEffect, useTransition } from 'react';
import { Skeleton } from '@/components/ui/skeleton';
import { useToast } from '@/hooks/use-toast';
import { getErrorMessage } from '@/lib/error-handler';
import type { Anomaly, DeadStockItem, Alert } from '@/types';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Button } from '@/components/ui/button';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { Tooltip, TooltipProvider, TooltipTrigger, TooltipContent } from '@/components/ui/tooltip';
import { cn } from '@/lib/utils';


interface InsightsData {
    summary: string;
    anomalies: Anomaly[];
    topDeadStock: DeadStockItem[];
    topLowStock: Alert[];
}

function AnomalyCard({ anomaly }: { anomaly: Anomaly }) {
  const [feedback, setFeedback] = useState<'helpful' | 'unhelpful' | null>(null);
  const [isPending, startTransition] = useTransition();
  const { toast } = useToast();

  const handleFeedback = (userFeedback: 'helpful' | 'unhelpful') => {
    startTransition(async () => {
        const formData = new FormData();
        formData.append('subjectId', anomaly.id!);
        formData.append('subjectType', 'anomaly_explanation');
        formData.append('feedback', userFeedback);
        
        const result = await logUserFeedback(formData);
        if (result.success) {
            setFeedback(userFeedback);
            toast({ title: 'Feedback Submitted', description: 'Thank you for helping us improve!' });
        } else {
            toast({ variant: 'destructive', title: 'Error', description: result.error });
        }
    });
  };

  const isRevenue = anomaly.anomaly_type === 'Revenue Anomaly';
  const currentValue = isRevenue ? anomaly.daily_revenue : anomaly.daily_customers;
  const averageValue = isRevenue ? anomaly.avg_revenue : anomaly.avg_customers;
  const deviation = Math.abs(currentValue - averageValue);
  const direction = currentValue > averageValue ? 'higher' : 'lower';
  const confidenceColor = anomaly.confidence === 'high' ? 'text-success' : anomaly.confidence === 'medium' ? 'text-amber-500' : 'text-destructive';
  
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
      <div className="mt-3 bg-muted/50 p-3 rounded-md space-y-2 border">
        <div className="flex items-center gap-2 text-sm">
            <BrainCircuit className="h-4 w-4 text-primary shrink-0" />
            <p><strong className="font-semibold">AI Explanation:</strong> {anomaly.explanation || "No explanation generated."}</p>
        </div>
        <div className="flex items-center justify-between text-xs text-muted-foreground">
            <span className={cn("font-semibold capitalize", confidenceColor)}>Confidence: {anomaly.confidence}</span>
            {anomaly.suggestedAction && 
              <Button asChild variant="link" size="sm" className="p-0 h-auto">
                <Link href={`/chat?q=${encodeURIComponent(anomaly.suggestedAction)}`}>{anomaly.suggestedAction}</Link>
              </Button>
            }
        </div>
        <div className="flex items-center justify-end gap-2 pt-2 border-t mt-2">
            <p className="text-xs text-muted-foreground mr-auto">Was this explanation helpful?</p>
            <Button
              variant="ghost"
              size="icon"
              className={cn("h-6 w-6", feedback === 'helpful' && "bg-success/20 text-success")}
              onClick={() => handleFeedback('helpful')}
              disabled={isPending || feedback !== null}
            >
              <ThumbsUp className="h-4 w-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className={cn("h-6 w-6", feedback === 'unhelpful' && "bg-destructive/20 text-destructive")}
              onClick={() => handleFeedback('unhelpful')}
              disabled={isPending || feedback !== null}
            >
              <ThumbsDown className="h-4 w-4" />
            </Button>
        </div>
      </div>
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

function ErrorState({ error, onRetry }: { error: string, onRetry: () => void }) {
    return (
        <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed border-destructive/50 bg-destructive/10">
            <motion.div
                initial={{ y: -20, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                transition={{ delay: 0.1, type: 'spring' }}
                className="bg-destructive/10 rounded-full p-4"
            >
                <ServerCrash className="h-12 w-12 text-destructive" />
            </motion.div>
            <h3 className="mt-6 text-xl font-semibold text-destructive">Could Not Load Insights</h3>
            <p className="mt-2 text-muted-foreground max-w-md">{error}</p>
            <Button onClick={onRetry} className="mt-6">
                Try Again
            </Button>
        </Card>
    );
}

function EmptyState() {
  return (
    <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
        className="bg-primary/10 rounded-full p-6"
      >
        <Lightbulb className="h-16 w-16 text-primary" />
      </motion.div>
      <h3 className="mt-6 text-xl font-semibold">No New Insights</h3>
      <p className="mt-2 text-muted-foreground">
        The AI hasn't found any significant anomalies or urgent actions in your recent data.
      </p>
    </Card>
  );
}

export default function InsightsPage() {
  const [insights, setInsights] = useState<InsightsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { toast } = useToast();

  const fetchInsights = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await getInsightsPageData();
      setInsights(data);
    } catch (e) {
      const errorMessage = getErrorMessage(e) || 'An unknown error occurred while loading insights.';
      setError(errorMessage);
      toast({
        variant: 'destructive',
        title: 'Error Fetching Insights',
        description: errorMessage,
      });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchInsights();
  }, []);
  
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
  
  if (error) {
    return (
        <AppPage>
            <AppPageHeader
                title="Proactive Insights"
                description="There was a problem analyzing your data."
            />
            <ErrorState error={error} onRetry={fetchInsights} />
        </AppPage>
    )
  }

  const noActionableItems = 
    insights?.anomalies.length === 0 &&
    insights?.topDeadStock.length === 0 &&
    insights?.topLowStock.length === 0;
    
  if (noActionableItems) {
     return (
        <AppPage>
             <AppPageHeader
                title="Proactive Insights"
                description="The engine automatically scans your recent data for significant events or deviations from normal patterns."
            />
            <EmptyState />
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
      {insights?.summary && (
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
              <p className="text-foreground/90">{insights.summary}</p>
          </CardContent>
        </Card>
      )}
      
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
                <div className="p-4 text-sm text-muted-foreground text-center">
                    <p>No anomalies found in your recent activity.</p>
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
    