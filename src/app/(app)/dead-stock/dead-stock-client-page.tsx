
'use client';

import type { DeadStockItem } from '@/types';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { TrendingDown, Package, Warehouse } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import { formatCentsAsCurrency } from '@/lib/utils';
import { motion } from 'framer-motion';

interface DeadStockClientPageProps {
  initialData: {
    deadStockItems: DeadStockItem[];
    totalValue: number;
    totalUnits: number;
    deadStockDays: number;
  };
}

const StatCard = ({ title, value, icon: Icon, description }: { title: string; value: string; icon: React.ElementType, description: string }) => (
    <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">{title}</CardTitle>
            <Icon className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
            <div className="text-2xl font-bold">{value}</div>
            <p className="text-xs text-muted-foreground">{description}</p>
        </CardContent>
    </Card>
);

export function DeadStockClientPage({ initialData }: DeadStockClientPageProps) {
  const { deadStockItems, totalValue, totalUnits, deadStockDays } = initialData;

  if (deadStockItems.length === 0) {
    return (
      <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
        <motion.div
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
          className="relative bg-primary/10 rounded-full p-6"
        >
          <TrendingDown className="h-16 w-16 text-primary" />
        </motion.div>
        <h3 className="mt-6 text-xl font-semibold">No Dead Stock Found!</h3>
        <p className="mt-2 text-muted-foreground">
          All your inventory has sold within the last {deadStockDays} days. Great job!
        </p>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
       <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <StatCard title="Dead Stock Value" value={formatCentsAsCurrency(totalValue)} icon={Warehouse} description="Total capital tied up in unsold items." />
          <StatCard title="Dead Stock Units" value={totalUnits.toLocaleString()} icon={Package} description="Total units considered dead stock." />
          <StatCard title="Analysis Period" value={`${deadStockDays} Days`} icon={TrendingDown} description="Items unsold for this duration." />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Dead Stock Report</CardTitle>
          <CardDescription>
            Products that have not sold in the last {deadStockDays} days and may require action.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Product</TableHead>
                  <TableHead className="text-right">Quantity</TableHead>
                  <TableHead className="text-right">Total Value</TableHead>
                  <TableHead>Last Sale Date</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {deadStockItems.map((item) => (
                  <TableRow key={item.sku}>
                    <TableCell>
                      <div className="font-medium">{item.product_name}</div>
                      <div className="text-xs text-muted-foreground">{item.sku}</div>
                    </TableCell>
                    <TableCell className="text-right font-tabular">{item.quantity}</TableCell>
                    <TableCell className="text-right font-medium font-tabular">{formatCentsAsCurrency(item.total_value)}</TableCell>
                    <TableCell>
                      {item.last_sale_date
                        ? formatDistanceToNow(new Date(item.last_sale_date), { addSuffix: true })
                        : 'Never'}
                    </TableCell>
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
