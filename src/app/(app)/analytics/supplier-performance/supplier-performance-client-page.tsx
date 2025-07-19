
'use client';

import type { SupplierPerformanceReport } from '@/types';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Award, TrendingUp, DollarSign } from 'lucide-react';
import { formatCentsAsCurrency } from '@/lib/utils';
import { motion } from 'framer-motion';

interface SupplierPerformanceClientPageProps {
  initialData: SupplierPerformanceReport[];
}

const StatCard = ({ title, value, icon: Icon }: { title: string; value: string; icon: React.ElementType }) => (
    <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">{title}</CardTitle>
            <Icon className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
            <div className="text-2xl font-bold">{value}</div>
        </CardContent>
    </Card>
);

export function SupplierPerformanceClientPage({ initialData }: SupplierPerformanceClientPageProps) {

  const totalProfit = initialData.reduce((sum, s) => sum + s.total_profit, 0);
  const averageSellThrough = initialData.length > 0 ? initialData.reduce((sum, s) => sum + s.sell_through_rate, 0) / initialData.length : 0;
  const topSupplierByProfit = initialData.sort((a,b) => b.total_profit - a.total_profit)[0];

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
          Supplier performance can be analyzed after you have some sales data recorded in the system.
        </p>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
       <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <StatCard title="Total Profit from Suppliers" value={formatCentsAsCurrency(totalProfit)} icon={DollarSign} />
          <StatCard title="Average Sell-Through" value={`${averageSellThrough.toFixed(1)}%`} icon={TrendingUp} />
          <StatCard title="Top Supplier by Profit" value={topSupplierByProfit?.supplier_name || 'N/A'} icon={Award} />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Supplier Performance Report</CardTitle>
          <CardDescription>
            A breakdown of which suppliers contribute most to your bottom line.
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
                  <TableHead className="text-right">Sell-Through Rate</TableHead>
                  <TableHead className="text-right">Products Sold</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {initialData.map((supplier) => (
                  <TableRow key={supplier.supplier_name}>
                    <TableCell className="font-medium">{supplier.supplier_name}</TableCell>
                    <TableCell className="text-right font-tabular">{formatCentsAsCurrency(supplier.total_profit)}</TableCell>
                    <TableCell className="text-right font-tabular">{supplier.average_margin.toFixed(1)}%</TableCell>
                    <TableCell className="text-right">
                        <Badge variant={supplier.sell_through_rate > 50 ? "secondary" : "outline"}
                               className={supplier.sell_through_rate > 75 ? 'bg-success/10 text-success-foreground' : ''}>
                            {supplier.sell_through_rate.toFixed(1)}%
                        </Badge>
                    </TableCell>
                    <TableCell className="text-right font-tabular">{supplier.distinct_products_sold}</TableCell>
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
