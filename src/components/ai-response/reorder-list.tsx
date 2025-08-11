
'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import type { ReorderSuggestion } from '@/types';
import { RefreshCw, Download } from 'lucide-react';
import { Button } from '../ui/button';
import { useToast } from '@/hooks/use-toast';
import Papa from 'papaparse';
import { formatCentsAsCurrency } from '@/lib/utils';

type ReorderListProps = {
  data: ReorderSuggestion[];
};

export function ReorderList({ data: items }: ReorderListProps) {
  const { toast } = useToast();

  const handleExport = () => {
    if (items.length === 0) {
      toast({ variant: 'destructive', title: 'No items to export' });
      return;
    }
    
    const dataToExport = items.map(s => ({
      SKU: s.sku,
      ProductName: s.product_name,
      Supplier: s.supplier_name,
      QuantityToOrder: s.suggested_reorder_quantity,
      UnitCost: s.unit_cost ? (s.unit_cost / 100).toFixed(2) : 'N/A',
      TotalCost: s.unit_cost ? ((s.suggested_reorder_quantity * s.unit_cost) / 100).toFixed(2) : 'N/A'
    }));

    const csv = Papa.unparse(dataToExport);
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', `reorder-suggestions-${new Date().toISOString().split('T')[0]}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    toast({ title: 'Export Complete' });
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
    <Card data-testid="reorder-list">
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
        <div className="max-h-80 overflow-y-auto pr-2 space-y-3">
            {items.map(item => (
                <div key={item.sku} className="rounded-lg border p-4 space-y-2 bg-muted/20">
                    <div className="flex justify-between items-start">
                        <div>
                            <h4 className="font-semibold">{item.product_name}</h4>
                            <p className="text-xs text-muted-foreground">{item.sku}</p>
                        </div>
                         <p className="text-lg font-bold text-primary">{item.suggested_reorder_quantity}</p>
                    </div>
                     <div className="text-xs text-muted-foreground border-t pt-2 mt-2">
                       {item.adjustment_reason}
                    </div>
                </div>
            ))}
        </div>
         <Button className="w-full mt-4" onClick={handleExport}>
            <Download className="mr-2 h-4 w-4" />
            Export Suggestions to CSV
        </Button>
      </CardContent>
    </Card>
  );
}
