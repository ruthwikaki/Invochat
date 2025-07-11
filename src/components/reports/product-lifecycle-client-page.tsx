
'use client';

import { useState } from 'react';
import type { ProductLifecycleAnalysis, ProductLifecycleStage } from '@/types';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { DataTable } from '@/components/ai-response/data-table';
import { Rocket, TrendingUp, CheckCircle, ArrowDownCircle, Info, Recycle } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { formatCentsAsCurrency } from '@/lib/utils';

const stageConfig = {
    Launch: { icon: Rocket, color: 'text-blue-500', bgColor: 'bg-blue-500/10', borderColor: 'border-blue-500/20' },
    Growth: { icon: TrendingUp, color: 'text-green-500', bgColor: 'bg-green-500/10', borderColor: 'border-green-500/20' },
    Maturity: { icon: CheckCircle, color: 'text-indigo-500', bgColor: 'bg-indigo-500/10', borderColor: 'border-indigo-500/20' },
    Decline: { icon: ArrowDownCircle, color: 'text-red-500', bgColor: 'bg-red-500/10', borderColor: 'border-red-500/20' },
};

function StageBadge({ stage }: { stage: ProductLifecycleStage['stage'] }) {
    const config = stageConfig[stage];
    return (
        <Badge variant="outline" className={cn("capitalize", config.bgColor, config.color, config.borderColor)}>
            <config.icon className="h-3 w-3 mr-1" />
            {stage}
        </Badge>
    );
}

function StageMetricCard({ title, count, icon: Icon, colorClass }: { title: string, count: number, icon: React.ElementType, colorClass: string }) {
    return (
        <Card className="flex-1">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">{title}</CardTitle>
                <Icon className={`h-4 w-4 text-muted-foreground ${colorClass}`} />
            </CardHeader>
            <CardContent>
                <div className="text-2xl font-bold">{count}</div>
                <p className="text-xs text-muted-foreground">products</p>
            </CardContent>
        </Card>
    );
}

interface ProductLifecycleClientPageProps {
  initialData: ProductLifecycleAnalysis;
}

export function ProductLifecycleClientPage({ initialData }: ProductLifecycleClientPageProps) {
  const [data] = useState(initialData);

  const formattedTableData = data.products.map(p => ({
    ...p,
    total_revenue: formatCentsAsCurrency(p.total_revenue),
  }));

  const chartData = [
    { name: 'Launch', count: data.summary.launch_count },
    { name: 'Growth', count: data.summary.growth_count },
    { name: 'Maturity', count: data.summary.maturity_count },
    { name: 'Decline', count: data.summary.decline_count },
  ];

  return (
    <div className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <StageMetricCard title="Launch" count={data.summary.launch_count} icon={Rocket} colorClass="text-blue-500" />
            <StageMetricCard title="Growth" count={data.summary.growth_count} icon={TrendingUp} colorClass="text-green-500" />
            <StageMetricCard title="Maturity" count={data.summary.maturity_count} icon={CheckCircle} colorClass="text-indigo-500" />
            <StageMetricCard title="Decline" count={data.summary.decline_count} icon={ArrowDownCircle} colorClass="text-red-500" />
        </div>

      <Card>
        <CardHeader>
          <CardTitle>Lifecycle Stage Distribution</CardTitle>
          <CardDescription>
            The number of products in each stage of their lifecycle.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="h-80 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="name" stroke="hsl(var(--muted-foreground))" fontSize={12} tickLine={false} axisLine={false} />
                <YAxis stroke="hsl(var(--muted-foreground))" fontSize={12} tickLine={false} axisLine={false} />
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'hsl(var(--background))',
                    borderColor: 'hsl(var(--border))',
                  }}
                  formatter={(value: number) => [value, 'Products']}
                />
                <Bar dataKey="count" name="Product Count" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Recycle className="h-5 w-5" /> Detailed Report</CardTitle>
          <CardDescription>
            Every product classified by its lifecycle stage based on sales trends.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {formattedTableData.length > 0 ? (
            <DataTable data={formattedTableData} />
          ) : (
            <p className="text-muted-foreground text-center">No products with sufficient sales data found for analysis.</p>
          )}
        </CardContent>
      </Card>
       <Card className="bg-muted/50 border-dashed">
            <CardHeader>
                <CardTitle className="flex items-center gap-2 text-muted-foreground"><Info className="h-5 w-5"/>How Stages Are Determined</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm text-muted-foreground">
                <p><strong>Launch:</strong> Recently added products with their first sales within the last 60 days.</p>
                <p><strong>Growth:</strong> Products with accelerating sales in the last 90 days compared to the 90 days prior.</p>
                <p><strong>Maturity:</strong> Products with stable, consistent sales over the past 180 days.</p>
                <p><strong>Decline:</strong> Products with decelerating sales and a decline in sales rank.</p>
            </CardContent>
        </Card>
    </div>
  );
}
