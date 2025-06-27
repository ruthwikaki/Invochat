'use client';

import { useState, useTransition, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { handleUserMessage } from '@/app/actions';
import type { Message, DashboardMetrics } from '@/types';
import { AlertTriangle, Sparkles, Send, Bot, BarChart2 } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { DataVisualization } from '@/components/chat/data-visualization';
import { getDashboardData } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import { SalesTrendChart } from '@/components/dashboard/sales-trend-chart';
import { InventoryCategoryChart } from '@/components/dashboard/inventory-category-chart';

// --- Components for the "AI Analyst" Tab ---

function AiAnalystPlaceholder() {
  return (
    <Card className="h-full flex flex-col items-center justify-center text-center p-8 border-dashed mt-4">
        <Sparkles className="h-16 w-16 text-muted-foreground" />
        <CardTitle className="mt-4">AI Analyst</CardTitle>
        <CardDescription className="mt-2 max-w-sm">
            Ask for any data visualization or report, and the AI will generate it for you.
        </CardDescription>
        <div className="mt-6 text-sm text-muted-foreground">
            <p className="font-semibold">Try these examples:</p>
            <ul className="mt-2 list-none space-y-1">
                <li>"Show a pie chart of inventory value by category"</li>
                <li>"What are my top 5 best selling products?"</li>
                <li>"List suppliers with low stock items"</li>
            </ul>
        </div>
    </Card>
  );
}

function LoadingState() {
  return (
    <Card className="mt-4">
        <CardHeader>
            <Skeleton className="h-6 w-1/2" />
            <Skeleton className="h-4 w-3/4" />
        </CardHeader>
        <CardContent className="space-y-4">
            <Skeleton className="h-64 w-full" />
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

function AiAnalyst() {
    const [query, setQuery] = useState('');
    const [isPending, startTransition] = useTransition();
    const [aiResponse, setAiResponse] = useState<Message | null>(null);
    const [error, setError] = useState<string | null>(null);

    const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        if (!query.trim() || isPending) return;

        setAiResponse(null);
        setError(null);
        
        startTransition(async () => {
            try {
                const response = await handleUserMessage({
                    conversationHistory: [{ role: 'user', content: query }],
                });
                
                if (response.content?.toLowerCase().includes('error')) {
                    setError(response.content)
                    setAiResponse(null);
                } else {
                    setAiResponse(response);
                    setError(null);
                }
            } catch (e: any) {
                setError(e.message || 'An unexpected error occurred.');
                setAiResponse(null);
            }
        });
    };

    return (
        <Card>
            <CardHeader>
                <CardTitle>Custom Report Generator</CardTitle>
                <CardDescription>
                    Use natural language to ask for specific data reports and visualizations.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <form onSubmit={handleSubmit} className="relative">
                    <Input
                        placeholder="e.g., 'Show me a bar chart of warehouse distribution'"
                        value={query}
                        onChange={(e) => setQuery(e.target.value)}
                        disabled={isPending}
                        className="pr-12 h-12 text-base"
                    />
                    <Button 
                        type="submit" 
                        size="icon" 
                        className="absolute right-2 top-1/2 -translate-y-1/2" 
                        disabled={!query.trim() || isPending}
                        aria-label="Generate Report"
                    >
                        <Send className="h-5 w-5" />
                    </Button>
                </form>

                <div className="mt-6">
                    {isPending ? (
                        <LoadingState />
                    ) : error ? (
                        <ErrorState error={error} />
                    ) : aiResponse ? (
                         <Card className="animate-fade-in mt-4">
                            <CardHeader>
                                <CardTitle className="flex items-center gap-2">
                                    <Sparkles className="h-5 w-5 text-primary" />
                                    AI Generated Report
                                </CardTitle>
                            </CardHeader>
                            <CardContent>
                                {aiResponse.content && <p className="mb-4 text-muted-foreground">{aiResponse.content}</p>}
                                {aiResponse.visualization ? (
                                    <DataVisualization
                                        visualization={aiResponse.visualization}
                                        title={aiResponse.visualization.config?.title}
                                    />
                                ) : (
                                    <p>The AI did not return a data visualization for this query.</p>
                                )}
                            </CardContent>
                        </Card>
                    ) : (
                        <AiAnalystPlaceholder />
                    )}
                </div>
            </CardContent>
        </Card>
    )
}

// --- Component for the "Key Metrics" Tab ---

function KeyMetricsReport() {
    const [data, setData] = useState<DashboardMetrics | null>(null);
    const [loading, setLoading] = useState(true);
    const { toast } = useToast();

    useEffect(() => {
        async function fetchData() {
            setLoading(true);
            try {
                const dashboardData = await getDashboardData();
                setData(dashboardData);
            } catch (error) {
                console.error("Failed to load key metrics", error);
                toast({ variant: 'destructive', title: 'Error', description: 'Could not load key metrics data.' });
            } finally {
                setLoading(false);
            }
        }
        fetchData();
    }, [toast]);

    if (loading) {
        return (
            <div className="grid gap-6 md:grid-cols-1 lg:grid-cols-2 mt-4">
                <Card>
                    <CardHeader><Skeleton className="h-6 w-1/2" /></CardHeader>
                    <CardContent><Skeleton className="h-80 w-full" /></CardContent>
                </Card>
                <Card>
                    <CardHeader><Skeleton className="h-6 w-1/2" /></CardHeader>
                    <CardContent><Skeleton className="h-80 w-full" /></CardContent>
                </Card>
            </div>
        )
    }

    if (!data) {
        return (
            <Card className="mt-4 text-center p-8">
                <CardTitle>Could not load metrics</CardTitle>
                <CardDescription>There was an issue fetching the pre-built reports.</CardDescription>
            </Card>
        );
    }

    return (
        <div className="grid gap-6 md:grid-cols-1 lg:grid-cols-2 mt-4">
            <SalesTrendChart data={data.salesTrendData} />
            <InventoryCategoryChart data={data.inventoryByCategoryData} />
        </div>
    )
}


export default function AnalyticsPage() {
    return (
        <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6 flex flex-col h-full">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <SidebarTrigger className="md:hidden" />
                <div>
                    <h1 className="text-2xl font-semibold">Analytics</h1>
                    <p className="text-muted-foreground text-sm">Explore your data and generate custom reports.</p>
                </div>
              </div>
            </div>

            <Tabs defaultValue="ai-analyst" className="flex-grow flex flex-col">
                <TabsList className="grid w-full grid-cols-2">
                    <TabsTrigger value="ai-analyst">
                        <Bot className="mr-2 h-4 w-4" />
                        AI Analyst
                    </TabsTrigger>
                    <TabsTrigger value="key-metrics">
                        <BarChart2 className="mr-2 h-4 w-4" />
                        Key Metrics
                    </TabsTrigger>
                </TabsList>

                <TabsContent value="ai-analyst" className="mt-4 flex-grow">
                    <AiAnalyst />
                </TabsContent>
                <TabsContent value="key-metrics" className="mt-4">
                    <KeyMetricsReport />
                </TabsContent>
            </Tabs>
        </div>
    );
}
