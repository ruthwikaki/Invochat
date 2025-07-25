

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
  </change>
  <change>
    <file>/src/components/ai-response/supplier-performance-table.tsx</file>
    <content><![CDATA[

'use client';

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import type { SupplierPerformanceReport } from '@/types';
import { Award } from 'lucide-react';
import { cn } from '@/lib/utils';
import { formatCentsAsCurrency } from '@/lib/utils';

type SupplierPerformanceTableProps = {
  data: SupplierPerformanceReport[];
};

export function SupplierPerformanceTable({ data }: SupplierPerformanceTableProps) {
  if (!data || data.length === 0) {
    return (
      <Card>
        <CardContent className="p-4 text-center text-muted-foreground">
          Not enough data to generate a supplier performance report.
        </CardContent>
      </Card>
    );
  }
  
  const getOnTimeBadgeVariant = (rate: number) => {
    if (rate >= 95) return 'bg-success/10 text-success-foreground border-success/20';
    if (rate >= 85) return 'bg-warning/10 text-amber-600 dark:text-amber-400 border-warning/20';
    return 'bg-destructive/10 text-destructive-foreground border-destructive/20';
  };

  return (
    <Card>
        <CardHeader>
            <CardTitle className="flex items-center gap-2">
                <Award className="h-5 w-5 text-primary" />
                Supplier Performance Report
            </CardTitle>
            <CardDescription>
                Analysis of supplier reliability and profitability.
            </CardDescription>
        </CardHeader>
        <CardContent>
            <div className="rounded-lg border max-h-96 overflow-auto">
                <Table>
                    <TableHeader>
                    <TableRow>
                        <TableHead>Supplier</TableHead>
                        <TableHead className="text-right">On-Time Rate</TableHead>
                        <TableHead className="text-right">Avg. Lead Time</TableHead>
                        <TableHead className="text-right">Total Profit</TableHead>
                    </TableRow>
                    </TableHeader>
                    <TableBody>
                    {data.map((supplier) => (
                        <TableRow key={supplier.supplier_name}>
                            <TableCell className="font-medium">{supplier.supplier_name}</TableCell>
                            <TableCell className="text-right">
                                <Badge variant="outline" className={cn('font-tabular', getOnTimeBadgeVariant(supplier.on_time_delivery_rate))}>
                                    {supplier.on_time_delivery_rate.toFixed(1)}%
                                </Badge>
                            </TableCell>
                            <TableCell className="text-right font-tabular">{supplier.average_lead_time_days ? `${supplier.average_lead_time_days.toFixed(1)} days` : 'N/A'}</TableCell>
                            <TableCell className="text-right font-tabular">{formatCentsAsCurrency(supplier.total_profit)}</TableCell>
                        </TableRow>
                    ))}
                    </TableBody>
                </Table>
            </div>
      </CardContent>
    </Card>
  );
}
