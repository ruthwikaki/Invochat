'use client';

import {
  AlertCircle,
  Package,
  TrendingDown,
  Truck,
  Warehouse,
} from 'lucide-react';
import Image from 'next/image';
import { Badge } from './ui/badge';
import { Button } from './ui/button';
import { Card, CardContent, CardHeader, CardTitle } from './ui/card';
import { SidebarTrigger } from './ui/sidebar';

function MetricCard({
  title,
  value,
  icon: Icon,
  className,
  label,
}: {
  title: string;
  value: string;
  icon: React.ElementType;
  className?: string;
  label?: string;
}) {
  return (
    <Card className={className}>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
        <Icon className="h-5 w-5 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{value}</div>
        {label && <p className="text-xs text-muted-foreground">{label}</p>}
      </CardContent>
    </Card>
  );
}

export function Dashboard() {
  return (
    <header className="sticky top-0 z-10 border-b bg-background/80 p-4 backdrop-blur-sm">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Dashboard</h1>
        </div>
      </div>
      <div className="mt-4 grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <Card className="col-span-1 lg:col-span-2">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-amber-400">
              <AlertCircle className="h-5 w-5" />
              Predictive Alerts
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm">
              You will run out of{' '}
              <span className="font-semibold text-primary-foreground">
                XYZ Cleaner
              </span>{' '}
              in <span className="font-semibold text-amber-400">7 days</span>.
            </p>
            <Button size="sm" className="mt-2">
              Reorder Now
            </Button>
          </CardContent>
        </Card>
        <MetricCard
          title="Inventory Value"
          value="$1.2M"
          icon={Package}
          label="+5.2% this month"
        />
        <MetricCard
          title="Dead Stock"
          value="$12,4k"
          icon={TrendingDown}
          className="border-destructive/50 text-destructive"
          label="-2.1% this month"
        />
        <MetricCard
          title="On-Time Deliveries"
          value="98.2%"
          icon={Truck}
          className="border-emerald-500/50 text-emerald-500"
          label="+1.5% this month"
        />
        <Card className="col-span-1 lg:col-span-3">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Warehouse className="h-5 w-5" />
              Multi-Warehouse View
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="relative h-48 w-full overflow-hidden rounded-lg">
              <Image
                src="https://placehold.co/800x400.png"
                alt="Map of warehouses"
                layout="fill"
                objectFit="cover"
                data-ai-hint="warehouse map"
              />
            </div>
          </CardContent>
        </Card>
      </div>
    </header>
  );
}
