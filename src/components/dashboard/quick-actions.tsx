
'use client';

import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Upload, MessageSquare, RefreshCw, AlertTriangle, GanttChartSquare } from 'lucide-react';
import { refreshData } from '@/app/(app)/actions';
import { useTransition } from 'react';
import { useToast } from '@/hooks/use-toast';
import { Loader2 } from 'lucide-react';

export const QuickActions = () => {
    const router = useRouter();
    const [isPending, startTransition] = useTransition();
    const { toast } = useToast();

    const handleRefresh = () => {
        startTransition(async () => {
            toast({ title: "Refreshing data...", description: "This may take a moment." });
            await refreshData();
            toast({ title: "Data refreshed!", description: "The latest data from your database is now being displayed." });
            router.refresh();
        });
    }

    return (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-4">
            <Button variant="outline" className="h-auto flex-col gap-2 p-4" onClick={() => router.push('/import')}>
                <Upload className="h-5 w-5" />
                <span>Import Data</span>
            </Button>
            <Button data-testid="ask-ai-button" variant="outline" className="h-auto flex-col gap-2 p-4" onClick={() => router.push('/chat')}>
                <MessageSquare className="h-5 w-5" />
                <span>Ask AI</span>
            </Button>
            <Button variant="outline" className="h-auto flex-col gap-2 p-4" onClick={() => router.push('/analytics/reordering')}>
                <RefreshCw className="h-5 w-5" />
                <span>Check Reorders</span>
            </Button>
            <Button variant="outline" className="h-auto flex-col gap-2 p-4" onClick={() => router.push('/analytics/dead-stock')}>
                <AlertTriangle className="h-5 w-5" />
                <span>Dead Stock</span>
            </Button>
             <Button variant="outline" className="h-auto flex-col gap-2 p-4 col-span-2 sm:col-span-1" onClick={handleRefresh} disabled={isPending}>
                {isPending ? <Loader2 className="h-5 w-5 animate-spin" /> : <GanttChartSquare className="h-5 w-5" />}
                <span>Refresh Data</span>
            </Button>
        </div>
    );
};
