
'use client';

import { Pie, PieChart, ResponsiveContainer, Tooltip, Cell, Legend } from 'recharts';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { PieChart as PieChartIcon } from 'lucide-react';

type InventoryCategoryChartProps = {
  data: { name: string; value: number }[];
};

const COLORS = ['#6B46C1', '#475569', '#10B981', '#F59E0B', '#F43F5E', '#3B82F6'];

const RADIAN = Math.PI / 180;
const renderCustomizedLabel = ({ cx, cy, midAngle, innerRadius, outerRadius, percent }: any) => {
  if (percent < 0.05) return null; // Don't render labels for tiny slices
  const radius = innerRadius + (outerRadius - innerRadius) * 0.5;
  const x = cx + radius * Math.cos(-midAngle * RADIAN);
  const y = cy + radius * Math.sin(-midAngle * RADIAN);

  return (
    <text x={x} y={y} fill="white" textAnchor="middle" dominantBaseline="central" className="text-xs font-medium">
      {`${(percent * 100).toFixed(0)}%`}
    </text>
  );
};


export function InventoryCategoryChart({ data }: InventoryCategoryChartProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
            <PieChartIcon className="h-5 w-5 text-primary" />
            Inventory Value by Category
        </CardTitle>
        <CardDescription>Distribution of inventory value across categories</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="h-80 w-full">
            {data && data.length > 0 ? (
                <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                    <Pie
                    data={data}
                    dataKey="value"
                    nameKey="name"
                    cx="50%"
                    cy="50%"
                    outerRadius="80%"
                    labelLine={false}
                    label={renderCustomizedLabel}
                    >
                    {data.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} stroke={COLORS[index % COLORS.length]} />
                    ))}
                    </Pie>
                    <Tooltip
                        contentStyle={{
                            backgroundColor: 'hsl(var(--background))',
                            borderColor: 'hsl(var(--border))',
                        }}
                        formatter={(value: number, name: string) => [value.toLocaleString('en-US', { style: 'currency', currency: 'USD' }), name]}
                    />
                    <Legend iconSize={10} />
                </PieChart>
                </ResponsiveContainer>
            ) : (
                <div className="flex h-full items-center justify-center text-muted-foreground">
                    No inventory data with categories found.
                </div>
            )}
        </div>
      </CardContent>
    </Card>
  );
}
