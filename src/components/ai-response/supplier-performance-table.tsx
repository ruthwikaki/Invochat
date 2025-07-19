
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

type SupplierPerformanceTableProps = {
  data: SupplierPerformanceReport[];
};

export function SupplierPerformanceTable({ data }: SupplierPerformanceTableProps) {
  if (data.length === 0) {
    return (
      <Card>
        <CardContent className="p-4 text-center text-muted-foreground">
          Not enough data to generate a supplier performance report.
        </CardContent>
      </Card>
    );
  }
  
  const getOnTimeBadgeVariant = (rate: number) => {
    if (rate >= 95) return 'bg-success/20 text-success-foreground border-success/30';
    if (rate >= 85) return 'bg-warning/20 text-amber-700 dark:text-amber-400 border-warning/30';
    return 'bg-destructive/20 text-destructive-foreground border-destructive/30';
  };

  return (
    <Card>
        <CardHeader>
            <CardTitle className="flex items-center gap-2">
                <Award className="h-5 w-5 text-primary" />
                Supplier Performance Report
            </CardTitle>
            <CardDescription>
                Analysis of supplier reliability based on completed purchase orders.
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
                        <TableHead className="text-right">Total Orders</TableHead>
                    </TableRow>
                    </TableHeader>
                    <TableBody>
                    {data.map((supplier) => (
                        <TableRow key={supplier.supplier_name}>
                            <TableCell className="font-medium">{supplier.supplier_name}</TableCell>
                            <TableCell className="text-right">
                                <Badge variant="outline" className={getOnTimeBadgeVariant(supplier.on_time_delivery_rate)}>
                                    {supplier.on_time_delivery_rate.toFixed(1)}%
                                </Badge>
                            </TableCell>
                            <TableCell className="text-right">{supplier.average_lead_time_days} days</TableCell>
                            <TableCell className="text-right">{supplier.total_completed_orders}</TableCell>
                        </TableRow>
                    ))}
                    </TableBody>
                </Table>
            </div>
      </CardContent>
    </Card>
  );
}
