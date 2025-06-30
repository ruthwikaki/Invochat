
'use client';

import { useState, useTransition } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { handleUserMessage } from '@/app/actions';
import type { Message } from '@/types';
import { AlertTriangle, Sparkles, TrendingUp, ChevronsRight, ArrowLeft, Activity, Pyramid, Loader2, Banknote } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';
import { DataVisualization } from '@/components/chat/data-visualization';
import Link from 'next/link';
import { getErrorMessage } from '@/lib/error-handler';
import { AppPage, AppPageHeader } from '@/components/ui/page';

function LoadingState() {
  return (
    <Card className="mt-4">
        <CardHeader>
            <Skeleton className="h-6 w-1/2" />
            <Skeleton className="h-4 w-3/4" />
        </CardHeader>
        <CardContent className="space-y-4">
            <Skeleton className="h-64 w-full" />
            <Skeleton className="h-4 w-1/4" />
        </CardContent>
    </Card>
  );
}

function ErrorState({ error }: { error: string }) {
  return (
    <Card className="border-destructive/50 mt-4">
        <CardHeader>
            <CardTitle className="flex items-center gap-2 text-destructive">
                <AlertTriangle className="h-5 w-5" />
                Report Generation Failed
            </CardTitle>
        </CardHeader>
        <CardContent>
            <p className="text-sm text-destructive">{error}</p>
        </CardContent>
    </Card>
  );
}

const availableAnalyses = [
    {
      key: 'abc',
      title: 'ABC Analysis',
      icon: Pyramid,
      description: 'Categorize products by revenue contribution (A, B, C) to identify your most critical inventory.',
      prompt: 'Perform ABC analysis on my inventory',
      details: "This analysis helps you prioritize which items to focus on for stock control, marketing, and sales efforts. 'A' items are your most valuable, 'C' items are the least."
    },
    {
      key: 'forecast',
      title: 'Demand Forecasting',
      icon: TrendingUp,
      description: 'Forecast sales for your top products for the next month based on historical trends.',
      prompt: "Forecast next month's demand for my top 10 products",
      details: "Uses linear regression on your past 12 months of sales data to project future demand, helping you with purchasing and stock level decisions."
    },
    {
        key: 'velocity',
        title: 'Sales Velocity Analysis',
        icon: Activity,
        description: 'Identify your fastest and slowest-selling products over the last 90 days.',
        prompt: 'Identify my 10 fastest and 10 slowest-moving products over the last 90 days based on units sold.',
        details: "This report shows you which products are moving quickly ('fast-movers') and which are not ('slow-movers'), allowing you to adjust marketing or consider discontinuing items."
    },
    {
        key: 'profit_margin',
        title: 'Profit Margin Analysis',
        icon: Banknote,
        description: 'Analyze gross profit margin by product and sales channel.',
        prompt: 'Analyze my gross profit margin by product and sales channel for the last 90 days.',
        details: "This report calculates your gross margin for each product, breaking it down by where the sale originated (e.g., Shopify, Amazon, Manual). It uses `(Selling Price - Landed Cost) / Selling Price` to determine profitability."
    },
    {
      key: 'margin_trends',
      title: 'Margin Trend Analysis',
      icon: TrendingUp,
      description: 'Analyze your gross profit margin trends over the last 12 months.',
      prompt: 'Show me my gross margin trend over the last 12 months, aggregated by month.',
      details: "This report calculates your gross margin month-over-month to help you identify trends in profitability. It uses `(SUM(selling_price * quantity) - SUM(cost_of_good * quantity)) / SUM(selling_price * quantity)`."
    }
];

function StrategicReports() {
    const [currentAnalysisKey, setCurrentAnalysisKey] = useState<string | null>(null);
    const [isPending, startTransition] = useTransition();
    const [analysisResult, setAnalysisResult] = useState<Message | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [conversationId, setConversationId] = useState<string | null>(null);

    const handleRunAnalysis = (prompt: string, key: string) => {
        setCurrentAnalysisKey(key);
        setAnalysisResult(null);
        setError(null);
        
        startTransition(async () => {
            try {
                const response = await handleUserMessage({
                    content: prompt,
                    conversationId: null,
                    source: 'analytics_page', 
                });
                
                if (response.error) {
                    setError(response.error);
                    setAnalysisResult(null);
                } else if (response.newMessage) {
                    setAnalysisResult(response.newMessage);
                    setConversationId(response.conversationId || null);
                    setError(null);
                }
            } catch (e) {
                setError(getErrorMessage(e) || 'An unexpected error occurred.');
                setAnalysisResult(null);
            }
        });
    };
    
    const currentAnalysisDetails = availableAnalyses.find(a => a.key === currentAnalysisKey);

    if (currentAnalysisKey && currentAnalysisDetails) {
        return (
            <Card>
                <CardHeader>
                    <Button variant="outline" size="sm" onClick={() => setCurrentAnalysisKey(null)} className="mb-4 w-fit">
                        <ArrowLeft className="mr-2 h-4 w-4" />
                        Back to All Reports
                    </Button>
                    <CardTitle className="flex items-center gap-2">
                        <Sparkles className="h-5 w-5 text-primary" />
                        {currentAnalysisDetails.title}
                    </CardTitle>
                    <CardDescription>{currentAnalysisDetails.details}</CardDescription>
                </CardHeader>
                <CardContent>
                     {isPending ? (
                        <LoadingState />
                    ) : error ? (
                        <ErrorState error={error} />
                    ) : analysisResult && (
                         <>
                            {analysisResult.content && <p className="mb-4 text-muted-foreground">{analysisResult.content}</p>}
                            {analysisResult.visualization ? (
                                <DataVisualization
                                    visualization={analysisResult.visualization}
                                    title={analysisResult.visualization.config?.title}
                                />
                            ) : (
                                <p>The AI did not return a data visualization for this query.</p>
                            )}
                            {conversationId && (
                                <Button asChild variant="link" className="mt-4">
                                    <Link href={`/chat?id=${conversationId}`}>View in Chat History <ChevronsRight className="h-4 w-4" /></Link>
                                </Button>
                            )}
                        </>
                    )}
                </CardContent>
            </Card>
        )
    }

    return (
        <div className="space-y-6">
            <Card className="bg-card">
                <CardHeader>
                    <CardTitle>AI-Powered Strategic Reports</CardTitle>
                    <CardDescription>
                       Run sophisticated analyses on your data with a single click. Each report is generated by the AI and saved as a new conversation in your chat history for future reference.
                    </CardDescription>
                </CardHeader>
            </Card>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-2 gap-6">
                {availableAnalyses.map((analysis) => (
                    <Card key={analysis.key} className="flex flex-col hover:shadow-lg transition-shadow duration-300">
                        <CardHeader className="flex-grow">
                            <div className="bg-primary/10 rounded-lg w-12 h-12 flex items-center justify-center mb-4">
                                <analysis.icon className="h-6 w-6 text-primary" />
                            </div>
                            <CardTitle>
                                {analysis.title}
                            </CardTitle>
                            <CardDescription>{analysis.description}</CardDescription>
                        </CardHeader>
                        <CardFooter>
                            <Button className="w-full" onClick={() => handleRunAnalysis(analysis.prompt, analysis.key)} disabled={isPending}>
                               {isPending && currentAnalysisKey === analysis.key ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
                                Run Analysis
                            </Button>
                        </CardFooter>
                    </Card>
                ))}
            </div>
        </div>
    );
}


export default function AnalyticsPage() {
    return (
        <AppPage className="flex flex-col h-full">
            <AppPageHeader 
                title="Strategic Reports"
                description="Generate deep-dive analyses with a single click."
            />
            <div className="flex-grow">
                <StrategicReports />
            </div>
        </AppPage>
    );
}
