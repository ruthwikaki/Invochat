import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { SidebarTrigger } from "@/components/ui/sidebar"
import { handleUserMessage } from "@/app/actions";
import type { ChartConfig } from "@/types";
import { DynamicChart } from "@/components/ai-response/dynamic-chart";
import { BarChart as BarChartIcon, AlertTriangle } from "lucide-react";
import type { Message, AssistantMessagePayload } from "@/types";

async function generateChart(message: string): Promise<ChartConfig | { error: string, query: string }> {
    try {
        const result = await handleUserMessage({ conversationHistory: [{ role: 'user', content: message }] });

        if (result.component === 'DynamicChart' && result.props) {
            return result.props as ChartConfig;
        }
        // If the AI returns a text response, treat it as an error for this context.
        return { error: `Could not generate chart. AI responded: ${result.content}`, query: message };

    } catch (e: any) {
        console.error(`Failed to generate chart for query: "${message}"`, e);
        return { error: e.message || 'An unknown error occurred.', query: message };
    }
}

function ErrorCard({ title, description }: { title: string, description: string }) {
    return (
        <Card className="border-destructive/50">
            <CardHeader>
                <CardTitle className="flex items-center gap-2 text-destructive">
                    <AlertTriangle className="h-5 w-5" />
                    {title}
                </CardTitle>
            </CardHeader>
            <CardContent>
                <p className="text-sm text-destructive">{description}</p>
            </CardContent>
        </Card>
    );
}

export default async function AnalyticsPage() {
    const chartQueries = [
        "Create a bar chart showing my inventory value by category",
        "Visualize my sales velocity by category as a pie chart"
    ];
    
    const results = await Promise.all(chartQueries.map(generateChart));

    return (
        <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <SidebarTrigger className="md:hidden" />
                <h1 className="text-2xl font-semibold">Analytics</h1>
              </div>
            </div>

            <div className="grid gap-6 md:grid-cols-1 lg:grid-cols-2">
                {results.map((chart, i) => (
                    <div key={i} className="min-w-0">
                        {'error' in chart ? (
                            <ErrorCard 
                                title={`Failed to load: "${chart.query}"`}
                                description={chart.error} 
                            />
                        ) : (
                            <DynamicChart {...chart} />
                        )}
                    </div>
                ))}
            </div>
             <Card>
                <CardHeader>
                    <CardTitle>Explore Your Data</CardTitle>
                     <CardDescription>Use the chat interface to ask for custom visualizations!</CardDescription>
                </CardHeader>
                <CardContent>
                    <div className="h-40 flex items-center justify-center text-muted-foreground bg-muted/50 rounded-lg text-center p-4">
                       Try asking: "Show me a pie chart of warehouse distribution"
                    </div>
                </CardContent>
            </Card>
        </div>
    )
}
