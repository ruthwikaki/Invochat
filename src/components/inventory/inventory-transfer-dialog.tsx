
'use client';

import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useTransition } from 'react';
import { useToast } from '@/hooks/use-toast';
import type { UnifiedInventoryItem, Location } from '@/types';
import { transferStock } from '@/app/data-actions';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Loader2 } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf';

const TransferStockSchema = z.object({
  product_id: z.string().uuid(),
  from_location_id: z.string().uuid(),
  to_location_id: z.string().uuid('Please select a destination location.'),
  quantity: z.coerce.number().int().positive('Quantity must be a positive number.'),
  notes: z.string().optional(),
}).refine(data => data.from_location_id !== data.to_location_id, {
  message: 'Source and destination locations cannot be the same.',
  path: ['to_location_id'],
});

type TransferStockData = z.infer<typeof TransferStockSchema>;

interface InventoryTransferDialogProps {
  item: UnifiedInventoryItem | null;
  locations: Location[];
  onClose: () => void;
  onTransferSuccess: () => void;
}

export function InventoryTransferDialog({ item, locations, onClose, onTransferSuccess }: InventoryTransferDialogProps) {
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();

  const form = useForm<TransferStockData>({
    resolver: zodResolver(TransferStockSchema),
    defaultValues: {
        product_id: item?.product_id,
        from_location_id: item?.location_id || undefined,
        quantity: 1,
    }
  });
  
  const onSubmit = (data: TransferStockData) => {
    startTransition(async () => {
      const formData = new FormData();
      Object.entries(data).forEach(([key, value]) => {
        if (value !== null && value !== undefined) {
          formData.append(key, String(value));
        }
      });
      const csrfToken = getCookie('csrf_token');
      if (csrfToken) formData.append(CSRF_FORM_NAME, csrfToken);

      const result = await transferStock(formData);
      if (result.success) {
        toast({ title: 'Stock Transferred', description: 'Inventory levels have been updated.' });
        onTransferSuccess();
      } else {
        toast({ variant: 'destructive', title: 'Error', description: result.error });
      }
    });
  };

  if (!item) return null;

  return (
    <Dialog open={!!item} onOpenChange={onClose}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Transfer Stock: {item.product_name}</DialogTitle>
          <DialogDescription>
            Move inventory from one location to another. Current location: {item.location_name || 'Unassigned'} ({item.quantity} units available).
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4 py-4">
            <input type="hidden" {...form.register('product_id')} value={item.product_id} />
            <input type="hidden" {...form.register('from_location_id')} value={item.location_id || ''} />

            <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                    <Label htmlFor="to_location_id">To Location</Label>
                    <Controller
                        name="to_location_id"
                        control={form.control}
                        render={({ field }) => (
                            <Select onValueChange={field.onChange} value={field.value}>
                                <SelectTrigger><SelectValue placeholder="Select destination" /></SelectTrigger>
                                <SelectContent>
                                    {locations.filter(loc => loc.id !== item.location_id).map(loc => (
                                        <SelectItem key={loc.id} value={loc.id}>{loc.name}</SelectItem>
                                    ))}
                                </SelectContent>
                            </Select>
                        )}
                    />
                     {form.formState.errors.to_location_id && <p className="text-sm text-destructive">{form.formState.errors.to_location_id.message}</p>}
                </div>
                <div className="space-y-2">
                    <Label htmlFor="quantity">Quantity to Transfer</Label>
                    <Input id="quantity" type="number" {...form.register('quantity')} max={item.quantity} />
                    {form.formState.errors.quantity && <p className="text-sm text-destructive">{form.formState.errors.quantity.message}</p>}
                </div>
            </div>
             <div className="space-y-2">
                <Label htmlFor="notes">Notes (Optional)</Label>
                <Textarea id="notes" {...form.register('notes')} placeholder="e.g., Transfer for storefront restock" />
            </div>

            <DialogFooter className="pt-4">
                <DialogClose asChild><Button type="button" variant="outline">Cancel</Button></DialogClose>
                <Button type="submit" disabled={isPending}>
                    {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Confirm Transfer
                </Button>
            </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
