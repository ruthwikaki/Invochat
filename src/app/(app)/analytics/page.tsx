import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { SidebarTrigger } from "@/components/ui/sidebar"
import { handleUserMessage } from "@/app/actions";
import type { ChartConfig } from "@/types";
import { DynamicChart } from "@/components/ai-response/dynamic-chart";
import { BarChart as BarChartIcon } from "lucide-react";


export default async function AnalyticsPage() {
    const chartQueries = [
        { message: "Create a bar chart showing my inventory value by category" },
        { message: "Visualize my sales velocity by category as a pie chart" }
    ];
    
    // This now awaits all promises. If any of the AI actions fail,
    // this will throw an error and be caught by the nearest error.tsx boundary.
    const chartPromises = chartQueries.map(query => handleUserMessage(query));
    const results = await Promise.all(chartPromises);

    const charts: ChartConfig[] = results
        .filter(c => c.component === 'DynamicChart' && c.props)
        .map(c => c.props as ChartConfig);

    return (
        <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <SidebarTrigger className="md:hidden" />
                <h1 className="text-2xl font-semibold">Analytics</h1>
              </div>
            </div>

            <div className="grid gap-6 md:grid-cols-1 lg:grid-cols-2">
                {charts.length > 0 ? (
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
                            <div className="h-60 flex flex-col items-center justify-center text-muted-foreground text-center">
                                <BarChartIcon className="h-12 w-12 mb-4" />
                                Could not generate charts. This can happen if the AI fails or if there is no data. Please ensure your database is populated and your API keys are configured.
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
