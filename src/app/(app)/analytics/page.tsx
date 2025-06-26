
'use client';

import { useState, useTransition } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { handleUserMessage } from '@/app/actions';
import type { AssistantMessagePayload } from '@/types';
import { DynamicChart } from '@/components/ai-response/dynamic-chart';
import { DataTable } from '@/components/ai-response/data-table';
import { AlertTriangle, Sparkles, Send, BarChart as BarChartIcon } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';

// A map to render different AI response components
const AiComponentMap = {
  DynamicChart,
  DataTable,
};

function PlaceholderContent() {
  return (
    <Card className="h-full flex flex-col items-center justify-center text-center p-8 border-dashed">
        <BarChartIcon className="h-16 w-16 text-muted-foreground" />
        <CardTitle className="mt-4">Dynamic Analytics</CardTitle>
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
    <Card>
        <CardHeader>
            <Skeleton className="h-6 w-1/2" />
            <Skeleton className="h-4 w-3/4" />
        </CardHeader>
        <CardContent className="space-y-4">
            <Skeleton className="h-48 w-full" />
            <Skeleton className="h-8 w-1/4" />
        </CardContent>
    </Card>
  );
}

function ErrorState({ error }: { error: string }) {
  return (
    <Card className="border-destructive/50">
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

export default function AnalyticsPage() {
    const [query, setQuery] = useState('');
    const [isPending, startTransition] = useTransition();
    const [aiResponse, setAiResponse] = useState<AssistantMessagePayload | null>(null);
    const [error, setError] = useState<string | null>(null);

    const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        if (!query.trim() || isPending) return;

        setAiResponse(null);
        setError(null);
        
        startTransition(async () => {
            try {
                // The conversation history for this one-off query is simple.
                // We don't need to pass the whole chat history, just the user's direct request.
                const response = await handleUserMessage({
                    conversationHistory: [{ role: 'user', content: query }],
                });
                
                if (response.content?.toLowerCase().includes('error')) {
                    setError(response.content)
                    setAiResponse(null);
                } else {
                    setAiResponse(response);
                }
            } catch (e: any) {
                setError(e.message || 'An unexpected error occurred.');
                setAiResponse(null);
            }
        });
    };

    const renderResponse = () => {
        if (!aiResponse) return null;

        const Component = aiResponse.component ? AiComponentMap[aiResponse.component as keyof typeof AiComponentMap] : null;

        return (
            <Card className="animate-fade-in">
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <Sparkles className="h-5 w-5 text-primary" />
                        AI Generated Report
                    </CardTitle>
                    {aiResponse.content && !Component && (
                         <CardDescription>{aiResponse.content}</CardDescription>
                    )}
                </CardHeader>
                <CardContent>
                    {Component ? (
                        <div className="space-y-4">
                            {aiResponse.content && <p className="text-muted-foreground">{aiResponse.content}</p>}
                            <Component {...aiResponse.props} />
                        </div>
                    ) : (
                        // If there's content but no component, show the content.
                        // If no content and no component, show a generic message.
                         aiResponse.content ? <p>{aiResponse.content}</p> : <p>The AI did not return a data visualization for this query.</p>
                    )}
                </CardContent>
            </Card>
        );
    };

    return (
        <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6 flex flex-col h-full">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <SidebarTrigger className="md:hidden" />
                <div>
                    <h1 className="text-2xl font-semibold">Analytics Playground</h1>
                    <p className="text-muted-foreground text-sm">Ask the AI to generate any report or visualization.</p>
                </div>
              </div>
            </div>

            <form onSubmit={handleSubmit} className="relative">
                <Input
                    placeholder="e.g., 'Show me a pie chart of warehouse distribution'"
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

            <div className="flex-grow">
                {isPending ? (
                    <LoadingState />
                ) : error ? (
                    <ErrorState error={error} />
                ) : aiResponse ? (
                    renderResponse()
                ) : (
                    <PlaceholderContent />
                )}
            </div>
        </div>
    );
}
