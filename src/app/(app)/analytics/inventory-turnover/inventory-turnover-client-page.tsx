
'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { TrendingUp, Package, DollarSign, LineChart } from 'lucide-react';
import { formatCentsAsCurrency } from '@/lib/utils';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';
import { motion } from 'framer-motion';

export interface TurnoverReport {
    turnover_rate: number;
    total_cogs: number;
    average_inventory_value: number;
    period_days: number;
}

interface InventoryTurnoverClientPageProps {
  report: TurnoverReport;
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

function EmptyState() {
    return (
        <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed h-full">
            <motion.div
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
                className="relative bg-primary/10 rounded-full p-6"
            >
                <LineChart className="h-16 w-16 text-primary" />
            </motion.div>
            <h3 className="mt-6 text-xl font-semibold">Not Enough Data for Turnover Report</h3>
            <p className="mt-2 text-muted-foreground max-w-sm">
                Inventory turnover is calculated using sales and product cost data. Once you have imported both, this report will become available.
            </p>
        </Card>
    );
}

export function InventoryTurnoverClientPage({ report }: InventoryTurnoverClientPageProps) {
  const { turnover_rate, total_cogs, average_inventory_value, period_days } = report;

  const chartData = [
    { name: 'Cost of Goods Sold', value: total_cogs },
    { name: 'Avg. Inventory Value', value: average_inventory_value },
  ];

  if (!total_cogs && !average_inventory_value) {
    return <EmptyState />;
  }

  return (
    <div className="space-y-6">
       <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <StatCard 
            title="Inventory Turnover Rate" 
            value={turnover_rate.toFixed(2)} 
            icon={TrendingUp} 
            description={`Over the last ${period_days} days.`} 
          />
          <StatCard 
            title="Total COGS" 
            value={formatCentsAsCurrency(total_cogs)} 
            icon={DollarSign} 
            description="Total cost of goods sold in the period." 
          />
          <StatCard 
            title="Avg. Inventory Value" 
            value={formatCentsAsCurrency(average_inventory_value)} 
            icon={Package} 
            description="Average value held as inventory." 
          />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Turnover Calculation</CardTitle>
          <CardDescription>
            This chart shows the two components used to calculate the turnover rate: Cost of Goods Sold / Average Inventory Value.
          </CardDescription>
        </CardHeader>
        <CardContent className="h-80">
           <ResponsiveContainer width="100%" height="100%">
            <BarChart data={chartData} layout="vertical" margin={{ left: 20 }}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis type="number" tickFormatter={(value) => formatCentsAsCurrency(value)} />
              <YAxis type="category" dataKey="name" width={150} />
              <Tooltip formatter={(value: number) => formatCentsAsCurrency(value)} />
              <Bar dataKey="value" fill="hsl(var(--primary))" radius={[0, 4, 4, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>
    </div>
  );
}
