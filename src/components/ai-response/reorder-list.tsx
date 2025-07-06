'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import type { ReorderSuggestion } from '@/types';
import { RefreshCw, ShoppingCart, Truck, Loader2 } from 'lucide-react';
import { Button } from '../ui/button';
import { useState, useTransition } from 'react';
import { useToast } from '@/hooks/use-toast';
import { createPurchaseOrdersFromSuggestions } from '@/app/data-actions';

type ReorderListProps = {
  items: ReorderSuggestion[];
};

export function ReorderList({ items }: ReorderListProps) {
  const [isPending, startTransition] = useTransition();
  const { toast } = useToast();

  const handleCreatePOs = () => {
    startTransition(async () => {
      const result = await createPurchaseOrdersFromSuggestions(items);
      if (result.success) {
        toast({
          title: 'Purchase Orders Created!',
          description: `${result.createdPoCount} new PO(s) have been generated. You can view them on the Purchase Orders page.`,
        });
      } else {
        toast({
          variant: 'destructive',
          title: 'Error Creating POs',
          description: result.error,
        });
      }
    });
  };
  
  if (!items || items.length === 0) {
    return (
      <Card>
        <CardContent className="p-4 text-center text-muted-foreground">
          No reorder suggestions available at this time.
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
            <RefreshCw className="h-5 w-5 text-primary"/>
            Reorder Suggestions
        </CardTitle>
        <CardDescription>
            The AI suggests reordering the following items based on sales velocity and stock levels.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {items.map(item => (
            <div key={item.sku} className="rounded-lg border p-4 space-y-2 bg-muted/20">
                <div className="flex justify-between items-start">
                    <div>
                        <h4 className="font-semibold">{item.product_name}</h4>
                        <p className="text-xs text-muted-foreground">{item.sku}</p>
                    </div>
                     <p className="text-lg font-bold text-primary">{item.suggested_reorder_quantity}</p>
                </div>
                <div className="flex justify-between items-center text-sm text-muted-foreground">
                    <p>Current: <span className="font-medium text-foreground">{item.current_quantity}</span></p>
                    <p>Reorder Point: <span className="font-medium text-warning">{item.reorder_point}</span></p>
                    <p>Supplier: <span className="font-medium text-foreground flex items-center gap-1"><Truck className="h-3 w-3"/>{item.supplier_name}</span></p>
                </div>
            </div>
        ))}
         <Button className="w-full mt-4" onClick={handleCreatePOs} disabled={isPending}>
            {isPending ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            ) : (
                <ShoppingCart className="mr-2 h-4 w-4" />
            )}
            {isPending ? 'Creating POs...' : 'Create Purchase Order(s)'}
        </Button>
      </CardContent>
    </Card>
  );
}
