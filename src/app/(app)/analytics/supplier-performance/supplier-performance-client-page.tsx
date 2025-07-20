
'use client';

import type { SupplierPerformanceReport } from '@/types';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Award, DollarSign, CheckCircle } from 'lucide-react';
import { formatCentsAsCurrency } from '@/lib/utils';
import { motion } from 'framer-motion';
import { cn } from '@/lib/utils';

interface SupplierPerformanceClientPageProps {
  initialData: SupplierPerformanceReport[];
}

const StatCard = ({ title, value, icon: Icon, description }: { title: string; value: string; icon: React.ElementType, description?: string }) => (
    <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">{title}</CardTitle>
            <Icon className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
            <div className="text-2xl font-bold">{value}</div>
            {description && <p className="text-xs text-muted-foreground">{description}</p>}
        </CardContent>
    </Card>
);

const getOnTimeBadgeVariant = (rate: number) => {
    if (rate >= 95) return 'bg-success/10 text-success-foreground border-success/20';
    if (rate >= 85) return 'bg-warning/10 text-amber-600 dark:text-amber-400 border-warning/20';
    return 'bg-destructive/10 text-destructive-foreground border-destructive/20';
};

export function SupplierPerformanceClientPage({ initialData }: SupplierPerformanceClientPageProps) {
  if (initialData.length === 0) {
    return (
      <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
        <motion.div
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
          className="relative bg-primary/10 rounded-full p-6"
        >
          <Award className="h-16 w-16 text-primary" />
        </motion.div>
        <h3 className="mt-6 text-xl font-semibold">Not Enough Data</h3>
        <p className="mt-2 text-muted-foreground">
          Supplier performance can be analyzed after you have some sales and purchase order data recorded in the system.
        </p>
      </Card>
    );
  }
  
  const topSupplierByProfit = [...initialData].sort((a,b) => b.total_profit - a.total_profit)[0];
  const topSupplierByOnTime = [...initialData].sort((a,b) => b.on_time_delivery_rate - a.on_time_delivery_rate)[0];

  return (
    <div className="space-y-6">
       <div className="grid gap-4 md:grid-cols-2">
          <StatCard title="Top Supplier (by Profit)" value={topSupplierByProfit?.supplier_name || 'N/A'} icon={DollarSign} description={`${formatCentsAsCurrency(topSupplierByProfit.total_profit)} total profit`} />
          <StatCard title="Top Supplier (by Reliability)" value={topSupplierByOnTime?.supplier_name || 'N/A'} icon={CheckCircle} description={`${topSupplierByOnTime.on_time_delivery_rate.toFixed(1)}% on-time rate`} />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Supplier Performance Report</CardTitle>
          <CardDescription>
            A breakdown of which suppliers contribute most to your bottom line and deliver reliably.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Supplier</TableHead>
                  <TableHead className="text-right">Total Profit</TableHead>
                  <TableHead className="text-right">Avg. Margin</TableHead>
                  <TableHead className="text-right">On-Time Rate</TableHead>
                  <TableHead className="text-right">Avg. Lead Time</TableHead>
                  <TableHead className="text-right">Completed POs</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {initialData.map((supplier) => (
                  <TableRow key={supplier.supplier_name}>
                    <TableCell className="font-medium">{supplier.supplier_name}</TableCell>
                    <TableCell className="text-right font-tabular">{formatCentsAsCurrency(supplier.total_profit)}</TableCell>
                    <TableCell className="text-right font-tabular">{supplier.average_margin.toFixed(1)}%</TableCell>
                    <TableCell className="text-right">
                        <Badge variant="outline" className={cn("font-tabular", getOnTimeBadgeVariant(supplier.on_time_delivery_rate))}>
                            {supplier.on_time_delivery_rate.toFixed(1)}%
                        </Badge>
                    </TableCell>
                    <TableCell className="text-right font-tabular">{supplier.average_lead_time_days ? `${supplier.average_lead_time_days.toFixed(1)} days` : 'N/A'}</TableCell>
                    <TableCell className="text-right font-tabular">{supplier.total_completed_orders}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
