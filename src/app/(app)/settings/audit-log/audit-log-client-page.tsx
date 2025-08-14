
'use client';

import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { format } from 'date-fns';
import { Search } from 'lucide-react';
import type { AuditLogEntry } from '@/types';
import { useTableState } from '@/hooks/use-table-state';

interface AuditLogClientPageProps {
  initialData: AuditLogEntry[];
  totalCount: number;
  itemsPerPage: number;
}

const PaginationControls = ({ totalCount, itemsPerPage, currentPage, onPageChange }: { totalCount: number; itemsPerPage: number; currentPage: number, onPageChange: (page: number) => void }) => {
    const totalPages = Math.ceil(totalCount / itemsPerPage);

    if (totalPages <= 1) {
        return null;
    }

    return (
        <div className="flex items-center justify-between p-4 border-t">
            <p className="text-sm text-muted-foreground">
                Showing page <strong>{currentPage}</strong> of <strong>{totalPages}</strong> ({totalCount} events)
            </p>
            <div className="flex items-center gap-2">
                <Button
                    variant="outline"
                    onClick={() => onPageChange(currentPage - 1)}
                    disabled={currentPage <= 1}
                >
                    Previous
                </Button>
                <Button
                    variant="outline"
                    onClick={() => onPageChange(currentPage + 1)}
                    disabled={currentPage >= totalPages}
                >
                    Next
                </Button>
            </div>
        </div>
    );
};

export function AuditLogClientPage({ initialData, totalCount, itemsPerPage }: AuditLogClientPageProps) {
    
    const {
        searchQuery,
        page,
        handleSearch,
        handlePageChange
    } = useTableState({ defaultSortColumn: 'created_at' });

    return (
        <Card>
            <CardHeader>
                <div className="relative">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                    <Input
                        placeholder="Search by action or user email..."
                        onChange={(e) => handleSearch(e.target.value)}
                        defaultValue={searchQuery}
                        className="pl-10"
                    />
                </div>
            </CardHeader>
            <CardContent className="p-0">
                <div className="max-h-[70vh] overflow-auto">
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Date</TableHead>
                                <TableHead>User</TableHead>
                                <TableHead>Action</TableHead>
                                <TableHead>Details</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {initialData.length === 0 ? (
                                <TableRow>
                                    <TableCell colSpan={4} className="h-24 text-center">
                                        No audit log entries found.
                                    </TableCell>
                                </TableRow>
                            ) : initialData.map((log) => (
                                <TableRow key={log.id}>
                                    <TableCell className="text-sm text-muted-foreground whitespace-nowrap">
                                        {format(new Date(log.created_at), 'MMM d, yyyy, h:mm a')}
                                    </TableCell>
                                    <TableCell>
                                        <Badge variant="secondary">{log.user_email || 'System'}</Badge>
                                    </TableCell>
                                    <TableCell className="font-medium">{log.action}</TableCell>
                                    <TableCell className="text-xs font-mono text-muted-foreground">
                                        {log.details ? JSON.stringify(log.details) : 'N/A'}
                                    </TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                </div>
                <PaginationControls totalCount={totalCount} itemsPerPage={itemsPerPage} currentPage={page} onPageChange={handlePageChange} />
            </CardContent>
        </Card>
    );
}

    