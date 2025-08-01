
'use client';

import { Bar, BarChart, ResponsiveContainer, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '../ui/card';
import { format } from 'date-fns';
import { formatCentsAsCurrency } from '@/lib/utils';
import { TrendingUp } from 'lucide-react';

interface SalesChartProps {
  data: { date: string; orders: number; revenue: number }[];
  currency: string;
}

export function SalesChart({ data, currency }: SalesChartProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Sales Overview</CardTitle>
        <CardDescription>
          Your total sales revenue over the selected period.
        </CardDescription>
      </CardHeader>
      <CardContent className="h-80">
        {data && data.length > 0 ? (
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={data}>
              <defs>
                <linearGradient id="colorUv" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.8}/>
                  <stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0.1}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border) / 0.5)" />
              <XAxis
                dataKey="date"
                stroke="hsl(var(--muted-foreground))"
                fontSize={12}
                tickLine={false}
                axisLine={false}
                tickFormatter={(str) => format(new Date(str), 'MMM d')}
              />
              <YAxis
                stroke="hsl(var(--muted-foreground))"
                fontSize={12}
                tickLine={false}
                axisLine={false}
                tickFormatter={(value) => formatCentsAsCurrency(value, currency).replace(/\.00$/, '').replace(/(\d)000$/, '$1k')}
                className="font-tabular"
              />
              <Tooltip
                cursor={{fill: 'hsl(var(--accent))'}}
                contentStyle={{
                  backgroundColor: 'hsl(var(--background) / 0.8)',
                  backdropFilter: 'blur(4px)',
                  borderColor: 'hsl(var(--border))',
                  borderRadius: 'var(--radius)',
                }}
                formatter={(value: number) => [formatCentsAsCurrency(value, currency), 'Sales']}
              />
              <Bar dataKey="revenue" fill="url(#colorUv)" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        ) : (
            <div className="h-full flex flex-col items-center justify-center text-center text-muted-foreground">
                <TrendingUp className="h-12 w-12 mb-4" />
                <p className="font-semibold">No Sales Data</p>
                <p className="text-sm">Connect an integration and sync your sales to see this chart.</p>
            </div>
        )}
      </CardContent>
    </Card>
  );
}
