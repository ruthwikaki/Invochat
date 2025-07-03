
'use client';

import { useState, useTransition } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { requestCompanyDataExport } from '@/app/data-actions';
import { DownloadCloud, Loader2, CheckCircle } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';

export default function ExportDataPage() {
    const [isPending, startTransition] = useTransition();
    const [jobId, setJobId] = useState<string | null>(null);
    const { toast } = useToast();

    const handleRequestExport = () => {
        startTransition(async () => {
            const result = await requestCompanyDataExport();
            if (result.success && result.jobId) {
                setJobId(result.jobId);
                toast({
                    title: 'Export Job Queued',
                    description: 'Your data export is being prepared. This may take a few minutes.'
                });
            } else {
                toast({
                    variant: 'destructive',
                    title: 'Error',
                    description: result.error || 'Could not start the export job.',
                });
            }
        });
    };

    return (
        <AppPage>
            <AppPageHeader
                title="Data Export"
                description="Request a complete archive of your company's data."
            />
            <Card className="max-w-2xl mx-auto">
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <DownloadCloud className="h-6 w-6 text-primary" />
                        Generate Data Archive
                    </CardTitle>
                    <CardDescription>
                        This tool will generate a ZIP file containing CSVs for all your major data tables, including inventory, orders, purchase orders, and customers.
                    </CardDescription>
                </CardHeader>
                <CardContent className="text-center">
                    {jobId ? (
                        <div className="flex flex-col items-center gap-4 p-8 bg-muted rounded-lg">
                            <CheckCircle className="h-16 w-16 text-success"/>
                            <h3 className="text-lg font-semibold">Export Job Started!</h3>
                            <p className="text-muted-foreground">
                                Your export (Job ID: {jobId}) is being processed. In a full production system, you would receive an email with a download link when it's ready.
                            </p>
                        </div>
                    ) : (
                        <Button size="lg" onClick={handleRequestExport} disabled={isPending}>
                            {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                            Request Full Data Export
                        </Button>
                    )}
                </CardContent>
                <CardFooter>
                    <p className="text-xs text-muted-foreground">
                        Exports are rate-limited. The generated file will be available for download for 24 hours.
                    </p>
                </CardFooter>
            </Card>
        </AppPage>
    );
}
