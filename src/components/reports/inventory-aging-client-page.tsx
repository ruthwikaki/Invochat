
'use client';

import { useState } from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import type { InventoryAgingReportItem } from '@/types';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { DataTable } from '@/components/ai-response/data-table';
import { Archive } from 'lucide-react';
import { formatCentsAsCurrency } from '@/lib/utils';

interface InventoryAgingClientPageProps {
  initialData: InventoryAgingReportItem[];
}

const processDataForChart = (data: InventoryAgingReportItem[]) => {
  const bins = {
    '0-30 Days': 0,
    '31-60 Days': 0,
    '61-90 Days': 0,
    '91-180 Days': 0,
    '181+ Days': 0,
  };

  data.forEach(item => {
    const days = item.days_since_last_sale;
    if (days <= 30) bins['0-30 Days'] += item.total_value;
    else if (days <= 60) bins['31-60 Days'] += item.total_value;
    else if (days <= 90) bins['61-90 Days'] += item.total_value;
    else if (days <= 180) bins['91-180 Days'] += item.total_value;
    else bins['181+ Days'] += item.total_value;
  });

  return Object.entries(bins).map(([name, value]) => ({ name, value: value / 100 }));
};

export function InventoryAgingClientPage({ initialData }: InventoryAgingClientPageProps) {
  const [data] = useState(initialData);
  const chartData = processDataForChart(data);
  const formattedTableData = data.map(item => ({
      ...item,
      total_value: formatCentsAsCurrency(item.total_value)
  }));

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Aging Summary by Value</CardTitle>
          <CardDescription>
            The total value of inventory sitting in different aging buckets.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="h-80 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="name" />
                <YAxis tickFormatter={(value) => `$${value / 1000}k`} />
                <Tooltip formatter={(value: number) => [formatCentsAsCurrency(value * 100), 'Value']} />
                <Legend />
                <Bar dataKey="value" fill="hsl(var(--primary))" name="Inventory Value" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Archive className="h-5 w-5" /> Detailed Report</CardTitle>
          <CardDescription>
            Every item in your inventory, sorted by the number of days since its last sale.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {formattedTableData.length > 0 ? (
            <DataTable data={formattedTableData} />
          ) : (
            <p className="text-muted-foreground text-center">No inventory items found.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

