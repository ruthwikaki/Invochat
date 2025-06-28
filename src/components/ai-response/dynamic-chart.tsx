
import type { ChartConfig } from '@/types';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Expand, Pencil, Download } from 'lucide-react';
import {
  Bar,
  BarChart,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  Cell,
  Legend
} from 'recharts';

type DynamicChartProps = ChartConfig & { isExpanded?: boolean };

function renderChart(props: DynamicChartProps) {
    const { chartType, data, config } = props;
    
    switch (chartType) {
        case 'bar':
            return (
                <BarChart data={data}>
                    <XAxis dataKey={config.xAxisKey || config.nameKey} stroke="hsl(var(--muted-foreground))" fontSize={12} tickLine={false} axisLine={false} />
                    <YAxis stroke="hsl(var(--muted-foreground))" fontSize={12} tickLine={false} axisLine={false} tickFormatter={(value) => `$${value}`} />
                    <Tooltip
                        contentStyle={{
                            backgroundColor: 'hsl(var(--background))',
                            borderColor: 'hsl(var(--border))'
                        }}
                    />
                    <Bar dataKey={config.dataKey} radius={[4, 4, 0, 0]}>
                        {data.map((entry, index) => (
                            <Cell key={`cell-${index}`} fill={`hsl(var(--chart-${(index % 5) + 1}))`} />
                        ))}
                    </Bar>
                </BarChart>
            );
        case 'pie':
            return (
                <PieChart>
                    <Pie
                        data={data}
                        dataKey={config.dataKey}
                        nameKey={config.nameKey}
                        cx="50%"
                        cy="50%"
                        outerRadius="80%"
                        innerRadius="50%"
                        paddingAngle={5}
                        labelLine={false}
                        label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                    >
                        {data.map((entry, index) => (
                            <Cell key={`cell-${index}`} fill={`hsl(var(--chart-${(index % 5) + 1}))`} />
                        ))}
                    </Pie>
                    <Tooltip 
                        contentStyle={{
                            backgroundColor: 'hsl(var(--background))',
                            borderColor: 'hsl(var(--border))'
                        }}
                    />
                    <Legend />
                </PieChart>
            );
        case 'line':
            return (
                <LineChart data={data}>
                    <XAxis dataKey={config.xAxisKey || config.nameKey} stroke="hsl(var(--muted-foreground))" fontSize={12} tickLine={false} axisLine={false} />
                    <YAxis stroke="hsl(var(--muted-foreground))" fontSize={12} tickLine={false} axisLine={false} />
                    <Tooltip
                        contentStyle={{
                            backgroundColor: 'hsl(var(--background))',
                            borderColor: 'hsl(var(--border))'
                        }}
                    />
                    <Line type="monotone" dataKey={config.dataKey} stroke="hsl(var(--primary))" />
                </LineChart>
            );
        default:
            return <p>Unsupported chart type.</p>;
    }
}


export function DynamicChart(props: DynamicChartProps) {
    if (!props.data || props.data.length === 0) {
        return <p>No data available to display the chart.</p>;
    }
    
    // If it's part of the full-screen dialog, just render the chart
    if (props.isExpanded) {
        return (
            <ResponsiveContainer width="100%" height="100%">
                {renderChart(props)}
            </ResponsiveContainer>
        )
    }

    // Otherwise, render it within the component container for the chat
    return (
        <div className="h-full w-full">
            <ResponsiveContainer width="100%" height="100%">
                {renderChart(props)}
            </ResponsiveContainer>
        </div>
    );
}
