
'use client';

import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { formatDistanceToNow } from 'date-fns';
import { Search, ThumbsUp, ThumbsDown, MessageSquare, Bot } from 'lucide-react';
import type { FeedbackWithMessages } from '@/types';
import { useTableState } from '@/hooks/use-table-state';
import { cn } from '@/lib/utils';
import DOMPurify from 'isomorphic-dompurify';

interface AiPerformanceClientPageProps {
  initialData: FeedbackWithMessages[];
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
                Showing page <strong>{currentPage}</strong> of <strong>{totalPages}</strong> ({totalCount} feedback entries)
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

export function AiPerformanceClientPage({ initialData, totalCount, itemsPerPage }: AiPerformanceClientPageProps) {
    
    const {
        searchQuery,
        page,
        handleSearch,
        handlePageChange
    } = useTableState({ defaultSortColumn: 'created_at' });

    return (
        <Card>
            <CardHeader>
                <CardTitle>AI Response Feedback</CardTitle>
                <CardDescription>
                    Review feedback provided by users on the AI&apos;s responses in the chat interface.
                </CardDescription>
                 <div className="relative pt-2">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                    <Input
                        placeholder="Search by user email or message content..."
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
                                <TableHead className="w-[120px]">Rating</TableHead>
                                <TableHead>Interaction</TableHead>
                                <TableHead className="w-[200px]">User</TableHead>
                                <TableHead className="w-[150px]">Date</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {initialData.length === 0 ? (
                                <TableRow>
                                    <TableCell colSpan={4} className="h-24 text-center">
                                        No feedback has been recorded yet.
                                    </TableCell>
                                </TableRow>
                            ) : initialData.map((feedback) => (
                                <TableRow key={feedback.id}>
                                    <TableCell>
                                        <Badge variant={feedback.feedback === 'helpful' ? 'secondary' : 'destructive'} className={cn(
                                            feedback.feedback === 'helpful' ? 'bg-success/10 text-success-foreground' : 'bg-destructive/10 text-destructive-foreground'
                                        )}>
                                            {feedback.feedback === 'helpful' ? 
                                                <ThumbsUp className="mr-2 h-4 w-4" /> : 
                                                <ThumbsDown className="mr-2 h-4 w-4" />
                                            }
                                            {feedback.feedback}
                                        </Badge>
                                    </TableCell>
                                    <TableCell>
                                        <div className="space-y-2">
                                            <div className="flex items-start gap-2 text-sm">
                                                <MessageSquare className="h-4 w-4 mt-1 text-muted-foreground shrink-0"/>
                                                <p className="font-medium">{feedback.user_message_content || 'N/A'}</p>
                                            </div>
                                            <div className="flex items-start gap-2 text-sm text-muted-foreground border-l-2 pl-4 ml-2">
                                                 <Bot className="h-4 w-4 mt-1 shrink-0"/>
                                                 <p dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(feedback.assistant_message_content || 'N/A') }} />
                                            </div>
                                        </div>
                                    </TableCell>
                                    <TableCell>
                                        <Badge variant="outline">{feedback.user_email || 'System'}</Badge>
                                    </TableCell>
                                    <TableCell className="text-sm text-muted-foreground whitespace-nowrap">
                                        {formatDistanceToNow(new Date(feedback.created_at), { addSuffix: true })}
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
