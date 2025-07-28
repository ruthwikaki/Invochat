
'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { CheckCircle, AlertTriangle, Clock, FileText } from "lucide-react";
import { formatDistanceToNow } from 'date-fns';
import { cn } from "@/lib/utils";

interface ImportJob {
    id: string;
    created_at: string;
    import_type: string;
    file_name: string;
    status: string;
    processed_rows: number | null;
    failed_rows: number | null;
}

interface ImportHistoryCardProps {
    initialHistory: ImportJob[];
}

const statusMap: Record<string, { icon: React.ElementType, color: string, text: string }> = {
    'completed': { icon: CheckCircle, color: 'text-success', text: 'Completed' },
    'completed_with_errors': { icon: AlertTriangle, color: 'text-warning', text: 'Completed with Errors' },
    'failed': { icon: AlertTriangle, color: 'text-destructive', text: 'Failed' },
    'processing': { icon: Clock, color: 'text-blue-500', text: 'Processing' },
};

export function ImportHistoryCard({ initialHistory }: ImportHistoryCardProps) {
    if (initialHistory.length === 0) {
        return null; // Don't render the card if there's no history
    }

    return (
        <Card>
            <CardHeader>
                <CardTitle className="flex items-center gap-2"><FileText /> Import History</CardTitle>
                <CardDescription>
                    A log of your recent data imports.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <div className="max-h-[300px] overflow-auto">
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>File Name</TableHead>
                                <TableHead>Type</TableHead>
                                <TableHead>Status</TableHead>
                                <TableHead>Rows Processed</TableHead>
                                <TableHead>Date</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {initialHistory.map(job => {
                                const statusInfo = statusMap[job.status] || { icon: AlertTriangle, color: 'text-muted-foreground', text: 'Unknown' };
                                return (
                                    <TableRow key={job.id}>
                                        <TableCell className="font-medium">{job.file_name}</TableCell>
                                        <TableCell>{job.import_type.replace(/-/g, ' ')}</TableCell>
                                        <TableCell>
                                            <div className={cn("flex items-center gap-2", statusInfo.color)}>
                                                <statusInfo.icon className="h-4 w-4" />
                                                {statusInfo.text}
                                            </div>
                                        </TableCell>
                                        <TableCell>
                                            {job.processed_rows !== null ? (
                                                <span className="font-tabular">{job.processed_rows} succeeded, {job.failed_rows || 0} failed</span>
                                            ) : 'N/A'}
                                        </TableCell>
                                        <TableCell>
                                            {formatDistanceToNow(new Date(job.created_at), { addSuffix: true })}
                                        </TableCell>
                                    </TableRow>
                                );
                            })}
                        </TableBody>
                    </Table>
                </div>
            </CardContent>
        </Card>
    );
}
