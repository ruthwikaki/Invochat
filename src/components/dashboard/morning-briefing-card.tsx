
'use client';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Lightbulb } from 'lucide-react';
import { Button } from '../ui/button';
import Link from 'next/link';
import { cn } from '@/lib/utils';

interface MorningBriefingCardProps {
    briefing: {
        greeting: string;
        summary: string;
        cta?: {
            text: string;
            link: string;
        };
    };
}

export function MorningBriefingCard({ briefing }: MorningBriefingCardProps) {
    return (
        <Card className="bg-gradient-to-r from-accent/20 to-transparent border-accent/20">
            <CardHeader>
                <CardTitle className="flex items-center gap-2 text-primary">
                    <Lightbulb className="h-5 w-5 text-accent" />
                    {briefing.greeting}
                </CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
                <p className="text-muted-foreground flex-1">{briefing.summary}</p>
                {briefing.cta && (
                    <Button asChild variant="secondary" className="bg-accent/30 hover:bg-accent/40 text-accent-foreground border-accent/20">
                        <Link href={briefing.cta.link}>{briefing.cta.text}</Link>
                    </Button>
                )}
            </CardContent>
        </Card>
    );
}
