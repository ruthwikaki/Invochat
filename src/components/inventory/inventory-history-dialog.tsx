
'use client';

import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getInventoryLedger, adjustInventoryQuantity } from '@/app/data-actions';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { format } from 'date-fns';
import type { InventoryLedgerEntry, UnifiedInventoryItem } from '@/types';
import { cn } from '@/lib/utils';
import { Package, ShoppingCart, RefreshCcw, AlertCircle, Loader2 } from 'lucide-react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Button } from '../ui/button';
import { Input } from '../ui/input';
import { Label } from '../ui/label';
import { useState, useTransition } from 'react';
import { useToast } from '@/hooks/use-toast';
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf-client';

interface InventoryHistoryDialogProps {
  variant: UnifiedInventoryItem | null;
  onClose: () => void;
}

const adjustmentSchema = z.object({
  newQuantity: z.coerce.number().int('Quantity must be a whole number.').min(0, 'Quantity cannot be negative.'),
  reason: z.string().min(3, 'A reason is required.').max(100, 'Reason is too long.'),
});

type AdjustmentFormData = z.infer<typeof adjustmentSchema>;

function StockAdjustmentForm({ variant, onSuccessfulSubmit }: { variant: UnifiedInventoryItem, onSuccessfulSubmit: () => void }) {
    const [isPending, startTransition] = useTransition();
    const { toast } = useToast();
    const queryClient = useQueryClient();

    const form = useForm<AdjustmentFormData>({
        resolver: zodResolver(adjustmentSchema),
        defaultValues: {
            newQuantity: variant.inventory_quantity,
            reason: '',
        }
    });
    
    const onSubmit = (data: AdjustmentFormData) => {
        startTransition(async () => {
            const formData = new FormData();
            const csrfToken = getCookie(CSRF_FORM_NAME);
            if (csrfToken) formData.append(CSRF_FORM_NAME, csrfToken);

            formData.append('variantId', variant.id);
            formData.append('newQuantity', String(data.newQuantity));
            formData.append('reason', data.reason);

            const result = await adjustInventoryQuantity(formData);

            if (result.success) {
                toast({ title: 'Inventory Updated', description: `Stock for ${variant.sku} has been set to ${data.newQuantity}.`});
                await queryClient.invalidateQueries({ queryKey: ['inventoryLedger', variant.id] });
                await queryClient.invalidateQueries({ queryKey: ['inventory']}); // To update the main list
                onSuccessfulSubmit();
            } else {
                toast({ variant: 'destructive', title: 'Update Failed', description: result.error });
            }
        });
    }

    return (
         <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4 pt-4 border-t">
            <h4 className="font-medium">Manual Stock Adjustment</h4>
            <div className="flex items-end gap-2">
                <div className="flex-1 space-y-1">
                    <Label htmlFor="newQuantity">New Quantity</Label>
                    <Input id="newQuantity" type="number" {...form.register('newQuantity')} />
                    {form.formState.errors.newQuantity && <p className="text-xs text-destructive">{form.formState.errors.newQuantity.message}</p>}
                </div>
                 <div className="flex-1 space-y-1">
                    <Label htmlFor="reason">Reason for Change</Label>
                    <Input id="reason" placeholder="e.g., Cycle count correction" {...form.register('reason')} />
                    {form.formState.errors.reason && <p className="text-xs text-destructive">{form.formState.errors.reason.message}</p>}
                </div>
                <Button type="submit" disabled={isPending}>
                    {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Adjust Stock
                </Button>
            </div>
        </form>
    )
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
            return { icon: AlertCircle, color: 'text-gray-500', label: 'Adjustment' };
    }
}

export function InventoryHistoryDialog({ variant, onClose }: InventoryHistoryDialogProps) {
  const { data: ledgerEntries, isLoading } = useQuery({
    queryKey: ['inventoryLedger', variant?.id],
    queryFn: () => {
        if (!variant) return Promise.resolve([]);
        return getInventoryLedger(variant.id);
    },
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
        <div className="py-4 space-y-4">
          <ScrollArea className="h-72">
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
           {variant && <StockAdjustmentForm variant={variant} onSuccessfulSubmit={() => {}} />}
        </div>
      </DialogContent>
    </Dialog>
  );
}
