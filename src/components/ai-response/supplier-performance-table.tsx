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