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

type DynamicChartProps = ChartConfig;

const COLORS = ['#6B46C1', '#475569', '#10B981', '#F59E0B', '#F43F5E'];

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
                    <Bar dataKey={config.dataKey} fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
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
                        outerRadius={80}
                        innerRadius={50}
                        paddingAngle={5}
                        fill="hsl(var(--primary))"
                        labelLine={false}
                        label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                    >
                        {data.map((entry, index) => (
                            <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
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

    return (
        <Card>
            <CardHeader className="flex flex-row items-center justify-between pb-2">
                <CardTitle className="text-base font-medium">{props.title}</CardTitle>
                <div className="flex items-center gap-1">
                    <Button variant="ghost" size="icon" className="h-6 w-6"><Expand className="h-4 w-4" /></Button>
                    <Button variant="ghost" size="icon" className="h-6 w-6"><Pencil className="h-4 w-4" /></Button>
                    <Button variant="ghost" size="icon" className="h-6 w-6"><Download className="h-4 w-4" /></Button>
                </div>
            </CardHeader>
            <CardContent>
                <div className="h-[250px] w-full">
                    <ResponsiveContainer width="100%" height="100%">
                        {renderChart(props)}
                    </ResponsiveContainer>
                </div>
            </CardContent>
        </Card>
    );
}
