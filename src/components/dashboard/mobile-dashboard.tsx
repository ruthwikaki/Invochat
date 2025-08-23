'use client';

import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle, SheetTrigger } from '@/components/ui/sheet';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Badge } from '@/components/ui/badge';
import { 
  Menu, 
  TrendingUp, 
  TrendingDown, 
  DollarSign, 
  Package, 
  Users, 
  AlertTriangle,
  Download,
  RefreshCw,
  Calendar
} from 'lucide-react';
import { ResponsiveContainer, AreaChart, Area, XAxis, YAxis, Tooltip } from 'recharts';
import { formatCentsAsCurrency } from '@/lib/utils';
import { DashboardMetrics } from '@/types';

interface MobileDashboardProps {
  initialMetrics: DashboardMetrics;
  currency: string;
}

interface RealTimeAlert {
  type: string;
  message: string;
  severity: 'info' | 'warning' | 'error';
  timestamp: string;
}

export function MobileDashboard({ initialMetrics, currency }: MobileDashboardProps) {
  const [metrics, setMetrics] = useState<DashboardMetrics>(initialMetrics);
  const [isLoading, setIsLoading] = useState(false);
  const [alerts, setAlerts] = useState<RealTimeAlert[]>([]);
  const [dateRange, setDateRange] = useState('30d');
  const [showMobileMenu, setShowMobileMenu] = useState(false);

  // Real-time data fetching
  useEffect(() => {
    const fetchRealTimeData = async () => {
      setIsLoading(true);
      try {
        const response = await fetch(`/api/analytics/enhanced?range=${dateRange}&realtime=true`);
        if (response.ok) {
          const data = await response.json();
          setMetrics(data);
          setAlerts(data.alerts || []);
        }
      } catch (error) {
        console.error('Failed to fetch real-time data:', error);
      } finally {
        setIsLoading(false);
      }
    };

    fetchRealTimeData();
    const interval = setInterval(fetchRealTimeData, 60000); // Update every minute
    return () => clearInterval(interval);
  }, [dateRange]);

  const kpiData = [
    {
      title: 'Revenue',
      value: formatCentsAsCurrency(metrics.total_revenue, currency),
      change: `${metrics.revenue_change?.toFixed(1) || 0}%`,
      changeType: (metrics.revenue_change || 0) >= 0 ? 'increase' : 'decrease',
      icon: DollarSign,
      color: 'emerald'
    },
    {
      title: 'Orders',
      value: metrics.total_orders?.toLocaleString() || '0',
      change: `${metrics.orders_change?.toFixed(1) || 0}%`,
      changeType: (metrics.orders_change || 0) >= 0 ? 'increase' : 'decrease',
      icon: Package,
      color: 'blue'
    },
    {
      title: 'Customers',
      value: metrics.new_customers?.toLocaleString() || '0',
      change: `${metrics.customers_change?.toFixed(1) || 0}%`,
      changeType: (metrics.customers_change || 0) >= 0 ? 'increase' : 'decrease',
      icon: Users,
      color: 'purple'
    }
  ];

  const MobileKpiCard = ({ kpi, index }: { kpi: typeof kpiData[0], index: number }) => (
    <motion.div
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ delay: index * 0.1 }}
    >
      <Card className="border-l-4 border-l-primary">
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div className="space-y-1">
              <p className="text-sm font-medium text-muted-foreground">{kpi.title}</p>
              <p className="text-xl font-bold">{kpi.value}</p>
              <div className="flex items-center space-x-1">
                {kpi.changeType === 'increase' ? (
                  <TrendingUp className="h-3 w-3 text-emerald-600" />
                ) : (
                  <TrendingDown className="h-3 w-3 text-red-600" />
                )}
                <span className={`text-xs font-medium ${
                  kpi.changeType === 'increase' ? 'text-emerald-600' : 'text-red-600'
                }`}>
                  {kpi.change}
                </span>
              </div>
            </div>
            <div className={`p-2 rounded-full bg-${kpi.color}-100`}>
              <kpi.icon className={`h-5 w-5 text-${kpi.color}-600`} />
            </div>
          </div>
        </CardContent>
      </Card>
    </motion.div>
  );

  return (
    <div className="space-y-4 px-4 pb-4">
      {/* Mobile Header */}
      <div className="flex items-center justify-between py-4">
        <div>
          <h1 className="text-2xl font-bold">Analytics</h1>
          <p className="text-sm text-muted-foreground">Mobile Dashboard</p>
        </div>
        
        <div className="flex items-center space-x-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => window.location.reload()}
            disabled={isLoading}
          >
            <RefreshCw className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
          </Button>
          
          <Sheet open={showMobileMenu} onOpenChange={setShowMobileMenu}>
            <SheetTrigger asChild>
              <Button variant="outline" size="sm">
                <Menu className="h-4 w-4" />
              </Button>
            </SheetTrigger>
            <SheetContent>
              <SheetHeader>
                <SheetTitle>Dashboard Options</SheetTitle>
                <SheetDescription>Customize your dashboard view</SheetDescription>
              </SheetHeader>
              <div className="space-y-4 mt-4">
                <div className="space-y-2">
                  <label className="text-sm font-medium">Date Range</label>
                  <Select value={dateRange} onValueChange={setDateRange}>
                    <SelectTrigger>
                      <Calendar className="h-4 w-4" />
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="7d">Last 7 Days</SelectItem>
                      <SelectItem value="30d">Last 30 Days</SelectItem>
                      <SelectItem value="90d">Last 90 Days</SelectItem>
                      <SelectItem value="365d">Last Year</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                
                <Button className="w-full" variant="outline">
                  <Download className="h-4 w-4 mr-2" />
                  Export Data
                </Button>
              </div>
            </SheetContent>
          </Sheet>
        </div>
      </div>

      {/* Real-time Alerts */}
      {alerts.length > 0 && (
        <Card className="border-orange-200 bg-orange-50">
          <CardContent className="p-4">
            <div className="flex items-center space-x-2 mb-2">
              <AlertTriangle className="h-4 w-4 text-orange-600" />
              <span className="text-sm font-medium text-orange-900">Live Alerts</span>
            </div>
            <ScrollArea className="h-20">
              {alerts.map((alert, index) => (
                <div key={index} className="flex items-center justify-between py-1">
                  <span className="text-xs text-orange-800">{alert.message}</span>
                  <Badge variant={alert.severity === 'error' ? 'destructive' : 'secondary'} className="text-xs">
                    {alert.severity}
                  </Badge>
                </div>
              ))}
            </ScrollArea>
          </CardContent>
        </Card>
      )}

      {/* Mobile KPI Cards */}
      <div className="space-y-3">
        {kpiData.map((kpi, index) => (
          <MobileKpiCard key={kpi.title} kpi={kpi} index={index} />
        ))}
      </div>

      {/* Mobile Sales Chart */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-lg">Sales Trend</CardTitle>
          <CardDescription className="text-sm">Revenue over time</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="h-48">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={metrics.sales_over_time || []}>
                <defs>
                  <linearGradient id="colorRevenue" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.3}/>
                    <stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0}/>
                  </linearGradient>
                </defs>
                <XAxis 
                  dataKey="date" 
                  axisLine={false}
                  tickLine={false}
                  className="text-xs"
                  tickFormatter={(date) => new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
                />
                <YAxis hide />
                <Tooltip 
                  contentStyle={{ 
                    backgroundColor: 'hsl(var(--background))', 
                    border: '1px solid hsl(var(--border))',
                    borderRadius: '8px',
                    fontSize: '12px'
                  }}
                  formatter={(value: number) => [formatCentsAsCurrency(value, currency), 'Revenue']}
                />
                <Area 
                  type="monotone" 
                  dataKey="revenue" 
                  stroke="hsl(var(--primary))" 
                  strokeWidth={2}
                  fill="url(#colorRevenue)"
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      {/* Mobile Top Products */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-lg">Top Products</CardTitle>
          <CardDescription className="text-sm">Best performers this period</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-3">
            {(metrics.top_products || []).slice(0, 3).map((product, index) => (
              <div key={product.product_id} className="flex items-center justify-between p-3 rounded-lg bg-muted/30">
                <div className="flex items-center space-x-3">
                  <div className="flex h-6 w-6 items-center justify-center rounded-full bg-primary text-primary-foreground text-xs font-bold">
                    {index + 1}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="font-medium text-sm truncate">{product.product_name}</p>
                    <p className="text-xs text-muted-foreground">{product.quantity_sold} sold</p>
                  </div>
                </div>
                <div className="text-right">
                  <p className="font-bold text-sm">{formatCentsAsCurrency(product.total_revenue, currency)}</p>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Quick Actions */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-lg">Quick Actions</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 gap-3">
            <Button variant="outline" className="h-16 flex-col space-y-1">
              <Package className="h-5 w-5" />
              <span className="text-xs">View Inventory</span>
            </Button>
            <Button variant="outline" className="h-16 flex-col space-y-1">
              <Users className="h-5 w-5" />
              <span className="text-xs">Customer List</span>
            </Button>
            <Button variant="outline" className="h-16 flex-col space-y-1">
              <TrendingUp className="h-5 w-5" />
              <span className="text-xs">Sales Report</span>
            </Button>
            <Button variant="outline" className="h-16 flex-col space-y-1">
              <Download className="h-5 w-5" />
              <span className="text-xs">Export Data</span>
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
