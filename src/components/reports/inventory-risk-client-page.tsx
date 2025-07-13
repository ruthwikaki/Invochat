

'use client';

import { useState } from 'react';
import type { InventoryRiskItem } from '@/types';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { DataTable } from '@/components/ai-response/data-table';
import { ShieldAlert } from 'lucide-react';
import { formatCentsAsCurrency } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';

interface InventoryRiskClientPageProps {
  initialData: InventoryRiskItem[];
}

function RiskBadge({ score }: { score: number }) {
  let variant: "destructive" | "default" | "secondary" = "secondary";
  let text = 'Low';

  if (score > 75) {
    variant = "destructive";
    text = 'High';
  } else if (score > 50) {
    variant = "default";
    text = 'Medium';
  }

  const badgeClasses = {
    destructive: "bg-destructive/10 text-destructive border-destructive/20",
    default: "bg-warning/10 text-amber-600 dark:text-amber-400 border-warning/20",
    secondary: "bg-success/10 text-emerald-600 dark:text-emerald-400 border-success/20",
  };

  return <Badge variant="outline" className={cn(badgeClasses[variant])}>{text}</Badge>;
}

const processDataForChart = (data: InventoryRiskItem[]) => {
  const bins = {
    'Low (0-50)': 0,
    'Medium (51-75)': 0,
    'High (76-100)': 0,
  };

  data.forEach(item => {
    if (item.risk_score <= 50) bins['Low (0-50)'] += 1;
    else if (item.risk_score <= 75) bins['Medium (51-75)'] += 1;
    else bins['High (76-100)'] += 1;
  });

  return Object.entries(bins).map(([name, value]) => ({ name, value }));
};


export function InventoryRiskClientPage({ initialData }: InventoryRiskClientPageProps) {
  const [data] = useState(initialData);
  const chartData = processDataForChart(data);
  const formattedTableData = data.map(item => ({
      ...item,
      risk_level: <RiskBadge score={item.risk_score} />,
      total_value: formatCentsAsCurrency(item.total_value),
  }));

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Risk Distribution by SKU Count</CardTitle>
          <CardDescription>
            The number of products falling into different risk categories.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="h-80 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="name" />
                <YAxis allowDecimals={false} />
                <Tooltip />
                <Legend />
                <Bar dataKey="value" fill="hsl(var(--primary))" name="Product Count" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><ShieldAlert className="h-5 w-5" /> Detailed Risk Report</CardTitle>
          <CardDescription>
            All products, sorted by their calculated risk score from highest to lowest.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {formattedTableData.length > 0 ? (
            <DataTable data={formattedTableData} />
          ) : (
            <p className="text-muted-foreground text-center">No inventory items found to analyze.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
