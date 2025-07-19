
'use client';

import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Upload, MessageSquare, RefreshCw, AlertTriangle } from 'lucide-react';

export const QuickActions = () => {
    const router = useRouter();
    return (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <Button variant="outline" className="h-auto flex-col gap-2 p-4" onClick={() => { router.push('/import'); }}>
            <Upload className="h-5 w-5" />
            <span>Import Data</span>
            </Button>
            <Button variant="outline" className="h-auto flex-col gap-2 p-4" onClick={() => { router.push('/chat'); }}>
            <MessageSquare className="h-5 w-5" />
            <span>Ask AI</span>
            </Button>
            <Button variant="outline" className="h-auto flex-col gap-2 p-4" onClick={() => { router.push('/analytics/reordering'); }}>
            <RefreshCw className="h-5 w-5" />
            <span>Check Reorders</span>
            </Button>
            <Button variant="outline" className="h-auto flex-col gap-2 p-4" onClick={() => { router.push('/analytics/dead-stock'); }}>
            <AlertTriangle className="h-5 w-5" />
            <span>View Alerts</span>
            </Button>
        </div>
    );
};
