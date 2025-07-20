
'use client';

import { useRef } from 'react';
import { motion, useInView } from 'framer-motion';
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Scatter,
  ScatterChart,
  Tooltip,
  Treemap,
  XAxis,
  YAxis,
} from 'recharts';

interface DynamicChartProps {
    chartType: 'bar' | 'pie' | 'line' | 'treemap' | 'scatter';
    data: Record<string, unknown>[];
    config: {
        dataKey: string;
        nameKey: string;
        xAxisKey?: string;
        yAxisKey?: string;
        [key: string]: unknown;
    };
    isExpanded?: boolean;
}

interface TreemapContentProps {
  depth?: number;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  index?: number;
  name?: string;
  value?: number;
}


// A new component to render the content of each treemap rectangle
// This provides better visual styling than the default.
const TreemapContent = (props: TreemapContentProps) => {
  const { depth, x, y, width, height, index, name, value } = props;

  // Add runtime checks to ensure props from recharts are present
  if (x === undefined || y === undefined || width === undefined || height === undefined || index === undefined || name === undefined || value === undefined || depth === undefined) {
    return null;
  }

  // Don't render text for very small boxes
  const showText = width > 60 && height > 25;

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
        rx={4}
        ry={4}
      />
      {depth === 1 && showText ? (
        <text x={x + 6} y={y + 18} fill="#fff" fontSize={14} fillOpacity={0.9} className="font-medium">
          {name}
        </text>
      ) : null}
      {depth === 1 && showText ? (
         <text x={x + 6} y={y + 36} fill="#fff" fontSize={12} fillOpacity={0.7}>
          {value.toLocaleString('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 })}
        </text>
      ) : null}
    </g>
  );
};


function renderChart(props: DynamicChartProps, isInView: boolean) {
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
                    <Bar dataKey={config.dataKey} radius={[4, 4, 0, 0]} isAnimationActive={isInView}>
                        {data.map((_, index) => (
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
                        isAnimationActive={isInView}
                        labelLine={false}
                        label={({ percent }) => percent > 0.05 ? `${(percent * 100).toFixed(0)}%` : ''}
                    >
                        {data.map((_, index) => (
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
                    <Line type="monotone" dataKey={config.dataKey} stroke="hsl(var(--primary))" isAnimationActive={isInView} />
                </LineChart>
            );
        case 'treemap':
            return (
                <Treemap
                    data={data}
                    dataKey={config.dataKey}
                    nameKey={config.nameKey}
                    aspectRatio={16 / 9}
                    isAnimationActive={isInView}
                    content={<TreemapContent />}
                >
                    <Tooltip
                        contentStyle={{
                            backgroundColor: 'hsl(var(--background))',
                            borderColor: 'hsl(var(--border))'
                        }}
                         formatter={(value: number, name: string) => [value.toLocaleString('en-US', { style: 'currency', currency: 'USD' }), name]}
                    />
                </Treemap>
            );
        case 'scatter':
            return (
                <ScatterChart
                    margin={{ top: 20, right: 30, bottom: 20, left: 20 }}
                >
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis 
                        type="number" 
                        dataKey={config.xAxisKey}
                        name={config.xAxisKey?.toString()}
                        stroke="hsl(var(--muted-foreground))"
                        fontSize={12}
                        tickLine={false}
                        axisLine={false}
                        tickFormatter={(value) => value.toLocaleString()}
                    />
                    <YAxis 
                        type="number" 
                        dataKey={config.yAxisKey}
                        name={config.yAxisKey?.toString()}
                        stroke="hsl(var(--muted-foreground))"
                        fontSize={12}
                        tickLine={false}
                        axisLine={false}
                        tickFormatter={(value) => value.toLocaleString()}
                    />
                    <Tooltip
                        cursor={{ strokeDasharray: '3 3' }}
                        contentStyle={{
                            backgroundColor: 'hsl(var(--background))',
                            borderColor: 'hsl(var(--border))'
                        }}
                    />
                    <Scatter name={config.nameKey || 'name'} dataKey={config.dataKey} fill="hsl(var(--primary))" isAnimationActive={isInView} />
                </ScatterChart>
            );
        default:
            return <p>Unsupported chart type.</p>;
    }
}


export function DynamicChart(props: DynamicChartProps) {
    const ref = useRef(null);
    const isInView = useInView(ref, { once: true, amount: 0.3 });

    if (props.data.length === 0) {
        return <p>No data available to display the chart.</p>;
    }
    
    // If it's part of the full-screen dialog, don't animate, just show it.
    if (props.isExpanded) {
        return (
            <ResponsiveContainer width="100%" height="100%">
                {renderChart(props, true)}
            </ResponsiveContainer>
        )
    }

    // Otherwise, render it within the component container for the chat with animation
    return (
        <motion.div
            ref={ref}
            initial={{ opacity: 0, y: 50 }}
            animate={{ opacity: isInView ? 1 : 0, y: isInView ? 0 : 50 }}
            transition={{ duration: 0.8, ease: "easeOut" }}
            className="h-full w-full"
        >
            <ResponsiveContainer width="100%" height="100%">
                {renderChart(props, isInView)}
            </ResponsiveContainer>
        </motion.div>
    );
}
