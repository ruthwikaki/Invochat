
'use client';

import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { TrendingUp } from 'lucide-react';
import { cn } from '@/lib/utils';
import { motion, useInView } from 'framer-motion';
import { useRef } from 'react';

type SalesTrendChartProps = {
  data: { date: string; Sales: number }[];
  className?: string;
};

export function SalesTrendChart({ data, className }: SalesTrendChartProps) {
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
              <TrendingUp className="h-5 w-5 text-primary" />
              Sales Trend
            </CardTitle>
            <CardDescription>Last 30 days of sales revenue</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="h-80 w-full">
              {data && data.length > 0 ? (
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart
                    data={data}
                    margin={{
                      top: 5,
                      right: 20,
                      left: 10,
                      bottom: 0,
                    }}
                  >
                    <CartesianGrid strokeDasharray="3 3" vertical={false} />
                    <XAxis
                      dataKey="date"
                      tickFormatter={(value) => new Date(value).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
                      stroke="hsl(var(--muted-foreground))"
                      fontSize={12}
                      tickLine={false}
                      axisLine={false}
                    />
                    <YAxis
                      stroke="hsl(var(--muted-foreground))"
                      fontSize={12}
                      tickLine={false}
                      axisLine={false}
                      tickFormatter={(value) => `$${(value / 1000).toFixed(0)}k`}
                    />
                    <Tooltip
                      contentStyle={{
                        backgroundColor: 'hsl(var(--background))',
                        borderColor: 'hsl(var(--border))',
                      }}
                      formatter={(value: number) => [value.toLocaleString('en-US', { style: 'currency', currency: 'USD' }), 'Sales']}
                    />
                    <Line 
                      type="monotone" 
                      dataKey="Sales" 
                      stroke="hsl(var(--primary))" 
                      strokeWidth={2} 
                      dot={false}
                      animationDuration={isInView ? 900 : 0}
                    />
                  </LineChart>
                </ResponsiveContainer>
              ) : (
                <div className="flex h-full items-center justify-center text-muted-foreground">
                  No sales data to display for this period.
                </div>
              )}
            </div>
          </CardContent>
        </Card>
    </motion.div>
  );
}
