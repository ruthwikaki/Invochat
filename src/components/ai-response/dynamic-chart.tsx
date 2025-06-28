
'use client';

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
  Legend,
  Treemap,
} from 'recharts';

type DynamicChartProps = ChartConfig & { isExpanded?: boolean };

// A new component to render the content of each treemap rectangle
// This provides better visual styling than the default.
const TreemapContent = (props: any) => {
  const { depth, x, y, width, height, index, name } = props;

  return (
    <g>
      <rect
        x={x}
        y={y}
        width={width}
        height={height}
        style={{
          fill: `hsl(var(--chart-${(index % 5) + 1}))`,
          stroke: 'hsl(var(--background))',
          strokeWidth: 2 / (depth + 1e-10),
          strokeOpacity: 1 / (depth + 1e-10),
        }}
      />
      {depth === 1 && width > 60 && height > 25 ? (
        <text x={x + 4} y={y + 18} fill="#fff" fontSize={14} fillOpacity={0.9}>
          {name}
        </text>
      ) : null}
    </g>
  );
};


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
        case 'treemap':
            return (
                <Treemap
                    data={data}
                    dataKey={config.dataKey}
                    nameKey={config.nameKey}
                    aspectRatio={4 / 3}
                    isAnimationActive={false} // Important for custom content
                    content={<TreemapContent />}
                >
                    <Tooltip
                        contentStyle={{
                            backgroundColor: 'hsl(var(--background))',
                            borderColor: 'hsl(var(--border))'
                        }}
                         formatter={(value: number, name: string) => [value.toLocaleString(), name]}
                    />
                </Treemap>
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
