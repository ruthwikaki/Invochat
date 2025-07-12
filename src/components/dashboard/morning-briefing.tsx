
'use client';

import { useState, useEffect } from 'react';
import { getMorningBriefing } from '@/app/data-actions';
import { Skeleton } from '../ui/skeleton';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '../ui/card';
import { Bot, Sun, ArrowRight, ServerCrash } from 'lucide-react';
import { Button } from '../ui/button';
import Link from 'next/link';

interface Briefing {
    greeting: string;
    summary: string;
    cta?: { text: string; link: string };
}

export function MorningBriefing({ dateRange }: { dateRange: string }) {
    const [briefing, setBriefing] = useState<Briefing | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        async function fetchBriefing() {
            try {
                setLoading(true);
                setError(null);
                const result = await getMorningBriefing(dateRange);
                setBriefing(result);
            } catch (e: any) {
                setError(e.message || 'Failed to load AI briefing.');
            } finally {
                setLoading(false);
            }
        }
        fetchBriefing();
    }, [dateRange]);

    if (loading) {
        return (
            <Card>
                <CardHeader className="flex flex-row items-center gap-3 space-y-0">
                    <Skeleton className="h-8 w-8 rounded-full" />
                    <div className="flex-1 space-y-1">
                        <Skeleton className="h-5 w-1/4" />
                        <Skeleton className="h-4 w-1/2" />
                    </div>
                </CardHeader>
                <CardContent className="space-y-2">
                    <Skeleton className="h-4 w-full" />
                    <Skeleton className="h-4 w-3/4" />
                    <Skeleton className="h-10 w-48 mt-2" />
                </CardContent>
            </Card>
        );
    }

    if (error || !briefing) {
        return (
            <Card className="border-destructive/50">
                 <CardHeader className="flex flex-row items-center gap-3 space-y-0">
                    <ServerCrash className="h-6 w-6 text-destructive" />
                     <div>
                        <CardTitle className="text-destructive">Briefing Unavailable</CardTitle>
                        <CardDescription className="text-destructive/80">{error}</CardDescription>
                     </div>
                 </CardHeader>
            </Card>
        );
    }

    return (
        <Card className="bg-gradient-to-br from-primary/10 to-primary/5 border-primary/20">
            <CardHeader className="flex flex-row items-center gap-3 space-y-0">
                <Bot className="h-6 w-6 text-primary" />
                <div>
                    <CardTitle>{briefing.greeting}</CardTitle>
                    <CardDescription>Here's your AI-powered summary for the day.</CardDescription>
                </div>
            </CardHeader>
            <CardContent className="space-y-4">
                <p className="text-lg">{briefing.summary}</p>
                {briefing.cta && (
                    <Button asChild>
                        <Link href={briefing.cta.link}>
                            {briefing.cta.text}
                            <ArrowRight className="ml-2 h-4 w-4" />
                        </Link>
                    </Button>
                )}
            </CardContent>
        </Card>
    );
}
