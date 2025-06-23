'use client'
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { SidebarTrigger } from "@/components/ui/sidebar"
import { Skeleton } from "@/components/ui/skeleton";
import { useAuth } from "@/context/auth-context";
import { handleUserMessage } from "@/app/actions";
import { useToast } from "@/hooks/use-toast";
import type { ChartConfig } from "@/types";
import { DynamicChart } from "@/components/ai-response/dynamic-chart";
import { useState, useEffect } from 'react';
import { BarChart as BarChartIcon } from "lucide-react";


export default function AnalyticsPage() {
    const [charts, setCharts] = useState<ChartConfig[]>([]);
    const [loading, setLoading] = useState(true);
    const { user, getIdToken } = useAuth();
    const { toast } = useToast();

    useEffect(() => {
        if (user) {
            const generateDefaultCharts = async () => {
                setLoading(true);
                try {
                    const token = await getIdToken();
                    if (!token) throw new Error("Authentication failed");

                    const chartQueries = [
                        "Create a bar chart showing my inventory value by category",
                        "Visualize my sales velocity by category as a pie chart"
                    ];
                    
                    const chartPromises = chartQueries.map(query => handleUserMessage({ message: query, idToken: token }));
                    const results = await Promise.all(chartPromises);

                    const validCharts = results
                        .filter(c => c.component === 'DynamicChart' && c.props)
                        .map(c => c.props as ChartConfig);
                    
                    setCharts(validCharts);

                } catch (error) {
                    console.error("Failed to generate charts:", error);
                    toast({
                        variant: 'destructive',
                        title: 'Error',
                        description: 'Could not generate analytics charts.'
                    })
                } finally {
                    setLoading(false);
                }
            };
            generateDefaultCharts();
        }
    }, [user, getIdToken, toast]);

    return (
        <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <SidebarTrigger className="md:hidden" />
                <h1 className="text-2xl font-semibold">Analytics</h1>
              </div>
            </div>

            <div className="grid gap-6 md:grid-cols-1 lg:grid-cols-2">
                {loading ? (
                    <>
                        <Card><CardHeader><Skeleton className="h-5 w-1/2"/></CardHeader><CardContent><Skeleton className="h-[300px] w-full"/></CardContent></Card>
                        <Card><CardHeader><Skeleton className="h-5 w-1/2"/></CardHeader><CardContent><Skeleton className="h-[300px] w-full"/></CardContent></Card>
                    </>
                ) : charts.length > 0 ? (
                    charts.map((chartProps, i) => (
                        <div key={i} className="min-w-0">
                            <DynamicChart {...chartProps} />
                        </div>
                    ))
                ) : (
                    <Card className="lg:col-span-2">
                        <CardHeader>
                            <CardTitle>No Data</CardTitle>
                        </CardHeader>
                        <CardContent>
                            <div className="h-60 flex flex-col items-center justify-center text-muted-foreground">
                                <BarChartIcon className="h-12 w-12 mb-4" />
                                Could not generate charts. Please ensure you have inventory and sales data.
                            </div>
                        </CardContent>
                    </Card>
                )}
            </div>
             <Card>
                <CardHeader>
                    <CardTitle>Explore Your Data</CardTitle>
                </CardHeader>
                <CardContent>
                    <div className="h-40 flex items-center justify-center text-muted-foreground">
                        Use the chat interface to ask for custom visualizations! For example: "Show me a pie chart of warehouse distribution"
                    </div>
                </CardContent>
            </Card>
        </div>
    )
}
