
'use client';

import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import React, { useTransition } from 'react';
import { useToast } from '@/hooks/use-toast';
import { InventoryUpdateSchema, type InventoryUpdateData, type UnifiedInventoryItem, type Location } from '@/types';
import { updateInventoryItem } from '@/app/data-actions';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Loader2 } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../ui/select';

interface InventoryEditDialogProps {
  item: UnifiedInventoryItem | null;
  onClose: () => void;
  onSave: (updatedItem: UnifiedInventoryItem) => void;
  locations: Location[];
}

export function InventoryEditDialog({ item, onClose, onSave, locations }: InventoryEditDialogProps) {
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();

  const form = useForm<InventoryUpdateData>({
    resolver: zodResolver(InventoryUpdateSchema),
    values: item ? {
      name: item.product_name,
      category: item.category || '',
      cost: item.cost,
      reorder_point: item.reorder_point,
      landed_cost: item.landed_cost,
      barcode: item.barcode,
      location_id: item.location_id
    } : undefined,
  });

  const onSubmit = (data: InventoryUpdateData) => {
    if (!item) return;

    startTransition(async () => {
      const result = await updateInventoryItem(item.sku, data);
      if (result.success && result.updatedItem) {
        toast({ title: 'Item Updated', description: `${result.updatedItem.product_name} has been successfully updated.` });
        onSave(result.updatedItem);
        onClose();
      } else {
        toast({ variant: 'destructive', title: 'Error', description: result.error });
      }
    });
  };
  
  React.useEffect(() => {
    if (item) {
      form.reset({
        name: item.product_name,
        category: item.category || '',
        cost: item.cost,
        reorder_point: item.reorder_point,
        landed_cost: item.landed_cost,
        barcode: item.barcode,
        location_id: item.location_id
      });
    }
  }, [item, form]);

  return (
    <Dialog open={!!item} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>Edit: {item?.product_name}</DialogTitle>
          <DialogDescription>
            Update the details for this inventory item. Note: Quantity cannot be changed here.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4 py-4">
          <div className="space-y-2">
            <Label htmlFor="name">Product Name</Label>
            <Input id="name" {...form.register('name')} />
            {form.formState.errors.name && <p className="text-sm text-destructive">{form.formState.errors.name.message}</p>}
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
                <Label htmlFor="category">Category</Label>
                <Input id="category" {...form.register('category')} />
            </div>
             <div className="space-y-2">
                <Label htmlFor="barcode">Barcode (UPC/EAN)</Label>
                <Input id="barcode" {...form.register('barcode')} />
            </div>
          </div>
           <div className="grid grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label htmlFor="cost">Cost</Label>
                <Input id="cost" type="number" step="0.01" {...form.register('cost')} />
                {form.formState.errors.cost && <p className="text-sm text-destructive">{form.formState.errors.cost.message}</p>}
              </div>
              <div className="space-y-2">
                <Label htmlFor="landed_cost">Landed Cost</Label>
                <Input id="landed_cost" type="number" step="0.01" {...form.register('landed_cost')} />
              </div>
               <div className="space-y-2">
                <Label htmlFor="reorder_point">Reorder Point</Label>
                <Input id="reorder_point" type="number" {...form.register('reorder_point')} />
                {form.formState.errors.reorder_point && <p className="text-sm text-destructive">{form.formState.errors.reorder_point.message}</p>}
              </div>
          </div>
          <div className="space-y-2">
            <Label htmlFor="location_id">Location</Label>
            <Controller
                name="location_id"
                control={form.control}
                render={({ field }) => (
                    <Select onValueChange={field.onChange} value={field.value || ''}>
                        <SelectTrigger>
                            <SelectValue placeholder="Assign a location" />
                        </SelectTrigger>
                        <SelectContent>
                             <SelectItem value="">Unassigned</SelectItem>
                            {locations.map(loc => (
                                <SelectItem key={loc.id} value={loc.id}>{loc.name}</SelectItem>
                            ))}
                        </SelectContent>
                    </Select>
                )}
            />
          </div>
          <DialogFooter className="pt-4">
            <DialogClose asChild>
              <Button type="button" variant="outline">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={isPending}>
              {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Save Changes
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
