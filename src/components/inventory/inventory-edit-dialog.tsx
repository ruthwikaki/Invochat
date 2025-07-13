
'use client';

import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import React, { useTransition } from 'react';
import { useToast } from '@/hooks/use-toast';
import { ProductUpdateSchema, type ProductUpdateData, type UnifiedInventoryItem } from '@/types';
import { updateProduct } from '@/app/data-actions';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Loader2 } from 'lucide-react';
import { Textarea } from '../ui/textarea';

interface InventoryEditDialogProps {
  item: UnifiedInventoryItem | null;
  onClose: () => void;
  onSave: (updatedItem: UnifiedInventoryItem) => void;
}

export function InventoryEditDialog({ item, onClose, onSave }: InventoryEditDialogProps) {
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();

  const form = useForm<ProductUpdateData>({
    resolver: zodResolver(ProductUpdateSchema),
    values: item ? {
      name: item.product_name,
      category: item.category || '',
      cost: item.cost,
      price: item.price,
      barcode: item.barcode,
      location_note: item.location_note,
    } : undefined,
  });

  const onSubmit = (data: ProductUpdateData) => {
    if (!item) return;

    startTransition(async () => {
      const result = await updateProduct(item.product_id, data);
      if (result.success && result.updatedItem) {
        toast({ title: 'Product Updated', description: `${result.updatedItem.product_name} has been successfully updated.` });
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
        price: item.price,
        barcode: item.barcode,
        location_note: item.location_note,
      });
    }
  }, [item, form]);

  return (
    <Dialog open={!!item} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Edit Product: {item?.product_name}</DialogTitle>
          <DialogDescription>
            Update the core details for this product. Stock levels are managed separately.
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
           <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="cost">Cost (in cents)</Label>
                <Input id="cost" type="number" step="1" {...form.register('cost')} />
                {form.formState.errors.cost && <p className="text-sm text-destructive">{form.formState.errors.cost.message}</p>}
              </div>
              <div className="space-y-2">
                <Label htmlFor="price">Price (in cents)</Label>
                <Input id="price" type="number" step="1" {...form.register('price')} />
                 {form.formState.errors.price && <p className="text-sm text-destructive">{form.formState.errors.price.message}</p>}
              </div>
          </div>
           <div className="space-y-2">
            <Label htmlFor="location_note">Location Note</Label>
            <Textarea id="location_note" {...form.register('location_note')} placeholder="e.g., Shelf A-3, Back room, Bin 42" />
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
