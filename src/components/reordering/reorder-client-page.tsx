
'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import type { ReorderSuggestion } from '@/types';
import { createPurchaseOrdersFromSuggestions } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Checkbox } from '@/components/ui/checkbox';
import { Button } from '@/components/ui/button';
import { Loader2, RefreshCw, ShoppingCart, AlertTriangle } from 'lucide-react';
import { AnimatePresence, motion } from 'framer-motion';

export function ReorderClientPage({ initialSuggestions }: { initialSuggestions: ReorderSuggestion[] }) {
  const router = useRouter();
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();
  const [selectedSuggestions, setSelectedSuggestions] = useState<ReorderSuggestion[]>([]);

  const handleSelect = (suggestion: ReorderSuggestion, checked: boolean) => {
    setSelectedSuggestions(prev => 
      checked ? [...prev, suggestion] : prev.filter(s => s.sku !== suggestion.sku)
    );
  };

  const handleSelectAll = (checked: boolean) => {
    setSelectedSuggestions(checked ? initialSuggestions : []);
  };

  const handleCreatePOs = () => {
    startTransition(async () => {
      const result = await createPurchaseOrdersFromSuggestions(selectedSuggestions);
      if (result.success) {
        toast({
          title: 'Purchase Orders Created!',
          description: `${result.createdPoCount} new PO(s) have been generated.`,
        });
        router.push('/purchase-orders');
      } else {
        toast({
          variant: 'destructive',
          title: 'Error Creating POs',
          description: result.error,
        });
      }
    });
  };
  
  const isAllSelected = initialSuggestions.length > 0 && selectedSuggestions.length === initialSuggestions.length;
  const isSomeSelected = selectedSuggestions.length > 0 && selectedSuggestions.length < initialSuggestions.length;
  
  if (initialSuggestions.length === 0) {
    return (
        <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
            <motion.div
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
                className="relative bg-primary/10 rounded-full p-6"
            >
                <RefreshCw className="h-16 w-16 text-primary" />
            </motion.div>
            <h3 className="mt-6 text-xl font-semibold">No Reorder Suggestions</h3>
            <p className="mt-2 text-muted-foreground">
                Your inventory levels are healthy, or there isn't enough sales data to make a suggestion.
            </p>
        </Card>
    )
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Suggested Items to Reorder</CardTitle>
          <CardDescription>Select items to automatically generate purchase orders grouped by supplier.</CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <div className="max-h-[65vh] overflow-auto">
            <Table>
              <TableHeader className="sticky top-0 z-10 bg-background/80 backdrop-blur-sm">
                <TableRow>
                  <TableHead className="w-12">
                    <Checkbox
                        checked={isAllSelected ? true : (isSomeSelected ? 'indeterminate' : false)}
                        onCheckedChange={handleSelectAll}
                    />
                  </TableHead>
                  <TableHead>Product</TableHead>
                  <TableHead>Supplier</TableHead>
                  <TableHead className="text-right">Current Qty</TableHead>
                  <TableHead className="text-right">Reorder Point</TableHead>
                  <TableHead className="text-right">Suggested Qty</TableHead>
                  <TableHead className="text-right">Unit Cost</TableHead>
                  <TableHead className="text-right">Total Cost</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {initialSuggestions.map(suggestion => (
                  <TableRow key={suggestion.sku} data-state={selectedSuggestions.some(s => s.sku === suggestion.sku) ? 'selected' : ''}>
                    <TableCell>
                      <Checkbox
                        checked={selectedSuggestions.some(s => s.sku === suggestion.sku)}
                        onCheckedChange={(checked) => handleSelect(suggestion, !!checked)}
                      />
                    </TableCell>
                    <TableCell>
                        <div className="font-medium">{suggestion.product_name}</div>
                        <div className="text-xs text-muted-foreground">{suggestion.sku}</div>
                    </TableCell>
                    <TableCell>{suggestion.supplier_name}</TableCell>
                    <TableCell className="text-right">{suggestion.current_quantity}</TableCell>
                    <TableCell className="text-right text-warning font-semibold">{suggestion.reorder_point}</TableCell>
                    <TableCell className="text-right font-bold text-primary">{suggestion.suggested_reorder_quantity}</TableCell>
                    <TableCell className="text-right">${suggestion.unit_cost.toFixed(2)}</TableCell>
                    <TableCell className="text-right font-medium">${(suggestion.suggested_reorder_quantity * suggestion.unit_cost).toFixed(2)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
      
       <AnimatePresence>
            {selectedSuggestions.length > 0 && (
                <motion.div
                    initial={{ y: 100, opacity: 0 }}
                    animate={{ y: 0, opacity: 1 }}
                    exit={{ y: 100, opacity: 0 }}
                    transition={{ type: 'spring', stiffness: 300, damping: 30 }}
                    className="fixed bottom-4 left-1/2 -translate-x-1/2 w-auto"
                >
                    <div className="flex items-center gap-4 bg-background/80 backdrop-blur-lg border rounded-full p-2 pl-4 shadow-2xl">
                        <p className="text-sm font-medium">{selectedSuggestions.length} item(s) selected</p>
                        <Button onClick={handleCreatePOs} disabled={isPending}>
                            {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                             <ShoppingCart className="mr-2 h-4 w-4" /> Create Purchase Order(s)
                        </Button>
                    </div>
                </motion.div>
            )}
        </AnimatePresence>
    </div>
  );
}
