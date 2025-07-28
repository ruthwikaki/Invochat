'use client';

import { useTransition } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { requestCompanyDataExport } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import { Loader2, Info } from 'lucide-react';

export function ExportDataClientPage() {
    const [isPending, startTransition] = useTransition();
    const { toast } = useToast();
    
    const handleRequestExport = () => {
        startTransition(async () => {
            const result = await requestCompanyDataExport();
            if (result.success) {
                toast({
                    title: "Export Queued",
                    description: `Your data export has been queued. You will be notified when it's ready.`,
                });
            } else {
                toast({
                    variant: 'destructive',
                    title: 'Export Failed',
                    description: result.error || 'An unknown error occurred.',
                });
            }
        });
    };

    return (
        <Card>
            <CardHeader>
                <CardTitle>Company Data Export</CardTitle>
                <CardDescription>
                    Generate a zip archive containing CSV files of all your data.
                </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
                <Alert>
                    <Info className="h-4 w-4" />
                    <AlertTitle>How It Works</AlertTitle>
                    <AlertDescription>
                        When you request an export, a job is queued to gather all your data. This process can take several minutes depending on the amount of data. Once complete, you will receive an email with a secure link to download your archive. The link will expire after 24 hours.
                    </AlertDescription>
                </Alert>
                <Button onClick={handleRequestExport} disabled={isPending}>
                    {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Request Full Data Export
                </Button>
            </CardContent>
        </Card>
    )
}
