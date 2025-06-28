
'use client';

import { Bar, BarChart, ResponsiveContainer, Tooltip, XAxis, YAxis, CartesianGrid, Cell } from 'recharts';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Users } from 'lucide-react';
import { cn } from '@/lib/utils';
import { motion, useInView } from 'framer-motion';
import { useRef } from 'react';

type TopCustomersChartProps = {
  data: { name: string; value: number }[];
  className?: string;
};

export function TopCustomersChart({ data, className }: TopCustomersChartProps) {
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
                <Users className="h-5 w-5 text-primary" />
                Top 5 Customers by Revenue
            </CardTitle>
            <CardDescription>Your most valuable customers by total spending</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="h-80 w-full">
                {data && data.length > 0 ? (
                    <ResponsiveContainer width="100%" height="100%">
                        <BarChart
                            layout="vertical"
                            data={data}
                            margin={{ top: 5, right: 30, left: 20, bottom: 5 }}
                        >
                            <CartesianGrid strokeDasharray="3 3" horizontal={false} />
                            <XAxis 
                                type="number" 
                                stroke="hsl(var(--muted-foreground))"
                                fontSize={12}
                                tickLine={false}
                                axisLine={false}
                                tickFormatter={(value) => `$${(value as number / 1000).toFixed(0)}k`}
                            />
                            <YAxis 
                                dataKey="name" 
                                type="category"
                                stroke="hsl(var(--muted-foreground))"
                                fontSize={12}
                                tickLine={false}
                                axisLine={false}
                                width={80}
                                style={{ textAnchor: 'end' }}
                            />
                            <Tooltip
                                contentStyle={{
                                    backgroundColor: 'hsl(var(--background))',
                                    borderColor: 'hsl(var(--border))',
                                }}
                                formatter={(value: number) => [value.toLocaleString('en-US', { style: 'currency', currency: 'USD' }), 'Total Spent']}
                                cursor={{ fill: 'hsl(var(--accent))' }}
                            />
                            <Bar dataKey="value" radius={[0, 4, 4, 0]} animationDuration={isInView ? 900 : 0}>
                                {data.map((entry, index) => (
                                    <Cell key={`cell-${index}`} fill={`hsl(var(--chart-${(index % 5) + 1}))`} />
                                ))}
                            </Bar>
                        </BarChart>
                    </ResponsiveContainer>
                ) : (
                    <div className="flex h-full items-center justify-center text-muted-foreground">
                        No customer spending data found.
                    </div>
                )}
            </div>
          </CardContent>
        </Card>
    </motion.div>
  );
}
