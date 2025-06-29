
'use client';

import { Pie, PieChart, ResponsiveContainer, Tooltip, Cell, Legend } from 'recharts';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { PieChart as PieChartIcon } from 'lucide-react';
import { cn } from '@/lib/utils';
import { motion, useInView } from 'framer-motion';
import { useRef } from 'react';

type InventoryCategoryChartProps = {
  data: { name: string; value: number }[];
  className?: string;
};

// Define a type for the label props to avoid 'any'
interface CustomizedLabelProps {
  cx: number;
  cy: number;
  midAngle: number;
  innerRadius: number;
  outerRadius: number;
  percent: number;
}

const RADIAN = Math.PI / 180;
const renderCustomizedLabel = ({ cx, cy, midAngle, innerRadius, outerRadius, percent }: CustomizedLabelProps) => {
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


export function InventoryCategoryChart({ data, className }: InventoryCategoryChartProps) {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, amount: 0.3 });

  return (
    <motion.div
        ref={ref}
        initial={{ opacity: 0, y: 50 }}
        animate={{ opacity: isInView ? 1 : 0, y: isInView ? 0 : 50 }}
        transition={{ duration: 0.8, ease: "easeOut" }}
        className={cn(className)}
    >
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
                        animationDuration={isInView ? 900 : 0}
                        >
                        {data.map((entry, index) => (
                            <Cell key={`cell-${index}`} fill={`hsl(var(--chart-${(index % 5) + 1}))`} stroke={`hsl(var(--chart-${(index % 5) + 1}))`} />
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
    </motion.div>
  );
}
