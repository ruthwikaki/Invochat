
'use client';

import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getInventoryLedger } from '@/app/data-actions';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { format } from 'date-fns';
import type { InventoryLedgerEntry, UnifiedInventoryItem } from '@/types';
import { cn } from '@/lib/utils';
import { ArrowDown, ArrowUp, Plus, Minus, Package, ShoppingCart, RefreshCcw } from 'lucide-react';

interface InventoryHistoryDialogProps {
  variant: UnifiedInventoryItem | null;
  onClose: () => void;
}

const getChangeTypeInfo = (type: string) => {
    switch (type) {
        case 'sale':
            return { icon: ShoppingCart, color: 'text-red-500', label: 'Sale' };
        case 'purchase_order':
            return { icon: Package, color: 'text-green-500', label: 'Purchase' };
        case 'reconciliation':
             return { icon: RefreshCcw, color: 'text-blue-500', label: 'Reconciliation' };
        case 'manual_adjustment':
        default:
            return { icon: Package, color: 'text-gray-500', label: 'Adjustment' };
    }
}

export function InventoryHistoryDialog({ variant, onClose }: InventoryHistoryDialogProps) {
  const { data: ledgerEntries, isLoading } = useQuery({
    queryKey: ['inventoryLedger', variant?.id],
    queryFn: () => getInventoryLedger(variant!.id),
    enabled: !!variant,
  });

  return (
    <Dialog open={!!variant} onOpenChange={onClose}>
      <DialogContent className="max-w-3xl">
        <DialogHeader>
          <DialogTitle>Inventory History: {variant?.product_title}</DialogTitle>
          <DialogDescription>
            Showing recent stock movements for SKU: {variant?.sku}
          </DialogDescription>
        </DialogHeader>
        <div className="py-4">
          <ScrollArea className="h-96">
            <Table>
              <TableHeader className="sticky top-0 bg-background z-10">
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Change Type</TableHead>
                  <TableHead className="text-right">Quantity Change</TableHead>
                  <TableHead className="text-right">New Quantity</TableHead>
                  <TableHead>Notes</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {isLoading ? (
                  Array.from({ length: 5 }).map((_, i) => (
                    <TableRow key={i}>
                      <TableCell><Skeleton className="h-4 w-24" /></TableCell>
                      <TableCell><Skeleton className="h-4 w-20" /></TableCell>
                      <TableCell className="text-right"><Skeleton className="h-4 w-8 ml-auto" /></TableCell>
                      <TableCell className="text-right"><Skeleton className="h-4 w-8 ml-auto" /></TableCell>
                      <TableCell><Skeleton className="h-4 w-32" /></TableCell>
                    </TableRow>
                  ))
                ) : ledgerEntries && ledgerEntries.length > 0 ? (
                  ledgerEntries.map((entry: InventoryLedgerEntry) => {
                    const { icon: Icon, color, label } = getChangeTypeInfo(entry.change_type);
                    const isPositive = entry.quantity_change > 0;
                    return (
                        <TableRow key={entry.id}>
                            <TableCell className="text-xs text-muted-foreground">{format(new Date(entry.created_at), 'PPp')}</TableCell>
                            <TableCell>
                                <Badge variant="outline" className={cn("border-opacity-50", color)}>
                                    <Icon className={cn("h-3 w-3 mr-1", color)} />
                                    {label}
                                </Badge>
                            </TableCell>
                            <TableCell className={cn("text-right font-medium", isPositive ? 'text-green-500' : 'text-red-500')}>
                                {isPositive ? `+${entry.quantity_change}` : entry.quantity_change}
                            </TableCell>
                            <TableCell className="text-right font-semibold">{entry.new_quantity}</TableCell>
                            <TableCell className="text-xs italic text-muted-foreground">{entry.notes}</TableCell>
                        </TableRow>
                    );
                  })
                ) : (
                  <TableRow>
                    <TableCell colSpan={5} className="text-center h-24">
                      No inventory history found for this variant.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </ScrollArea>
        </div>
      </DialogContent>
    </Dialog>
  );
}
