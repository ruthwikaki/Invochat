

'use client';

import { useState, useEffect } from 'react';
import { getInventoryLedger } from '@/app/data-actions';
import type { InventoryLedgerEntry } from '@/types';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogClose } from '@/components/ui/dialog';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Skeleton } from '@/components/ui/skeleton';
import { useToast } from '@/hooks/use-toast';
import { getErrorMessage } from '@/lib/error-handler';
import { format, formatDistanceToNow } from 'date-fns';
import { ArrowDown, ArrowUp, History, Package } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';

interface InventoryHistoryDialogProps {
  variantId: string | null;
  onClose: () => void;
}

function ChangeTypeBadge({ changeType }: { changeType: string }) {
    const variants: Record<string, string> = {
        'restock': 'bg-blue-500/10 text-blue-700 border-blue-500/20',
        'sale': 'bg-red-500/10 text-red-700 border-red-500/20',
        'return': 'bg-green-500/10 text-green-700 border-green-500/20',
        'adjustment': 'bg-gray-500/10 text-gray-700 border-gray-500/20',
    };
    return (
        <Badge variant="outline" className={cn("capitalize", variants[changeType] || variants.adjustment)}>
            {changeType.replace(/_/g, ' ')}
        </Badge>
    );
}

function HistoryTableRow({ entry }: { entry: any }) { // Using any for now
    const [formattedDate, setFormattedDate] = useState('');

    useEffect(() => {
        setFormattedDate(formatDistanceToNow(new Date(entry.created_at), { addSuffix: true }));
    }, [entry.created_at]);

    return (
        <TableRow key={entry.id}>
            <TableCell>
                <div className="font-medium" title={format(new Date(entry.created_at), 'PPP p')}>
                    {formattedDate}
                </div>
            </TableCell>
            <TableCell>
                <ChangeTypeBadge changeType={entry.adjustment_type} />
            </TableCell>
            <TableCell className={cn("text-right font-bold", entry.quantity_change > 0 ? 'text-success' : 'text-destructive')}>
                <span className="flex items-center justify-end gap-1">
                    {entry.quantity_change > 0 ? <ArrowUp className="h-3 w-3" /> : <ArrowDown className="h-3 w-3" />}
                    {entry.quantity_change}
                </span>
            </TableCell>
            <TableCell className="text-right">{entry.new_quantity}</TableCell>
            <TableCell>{entry.reason || 'N/A'}</TableCell>
        </TableRow>
    )
}

export function InventoryHistoryDialog({ variantId, onClose }: InventoryHistoryDialogProps) {
  const [history, setHistory] = useState<any[]>([]); // Using any for now
  const [loading, setLoading] = useState(false);
  const { toast } = useToast();

  useEffect(() => {
    if (variantId) {
      const fetchHistory = async () => {
        setLoading(true);
        try {
          // This action needs to be updated to fetch from inventory_adjustments
          // const data = await getInventoryLedger(variantId);
          // setHistory(data);
          toast({ title: "History Temporarily Unavailable", description: "This feature is being updated for the new database schema."})
        } catch (error) {
          toast({
            variant: 'destructive',
            title: 'Error',
            description: getErrorMessage(error),
          });
        } finally {
          setLoading(false);
        }
      };
      fetchHistory();
    }
  }, [variantId, toast]);

  return (
    <Dialog open={!!variantId} onOpenChange={onClose}>
      <DialogContent className="max-w-3xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <History className="h-5 w-5" />
            Inventory History for Variant
          </DialogTitle>
          <DialogDescription>
            A complete audit trail of all stock movements for this item.
          </DialogDescription>
        </DialogHeader>
        <div className="max-h-[60vh] overflow-y-auto">
          {loading ? (
            <div className="space-y-2 p-4">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-10 w-full" />
              ))}
            </div>
          ) : history.length === 0 ? (
            <div className="flex flex-col items-center justify-center text-center p-8 border-2 border-dashed rounded-lg h-60">
              <Package className="h-12 w-12 text-muted-foreground" />
              <h3 className="mt-4 font-semibold">No History Found</h3>
              <p className="text-sm text-muted-foreground">There are no recorded stock movements for this item.</p>
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead className="text-right">Change</TableHead>
                  <TableHead className="text-right">New Quantity</TableHead>
                  <TableHead>Reference/Notes</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {history.map((entry) => (
                  <HistoryTableRow key={entry.id} entry={entry} />
                ))}
              </TableBody>
            </Table>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
