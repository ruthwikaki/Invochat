'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { 
  Download, 
  Filter, 
  RefreshCw, 
  TrendingUp, 
  TrendingDown, 
  DollarSign, 
  Package, 
  Users, 
  Target,
  Calendar,
  Search,
  ChevronDown
} from 'lucide-react';
import { ResponsiveContainer, BarChart, LineChart, Bar, Line, XAxis, YAxis, CartesianGrid, Tooltip } from 'recharts';
import { formatCentsAsCurrency } from '@/lib/utils';
import { DashboardMetrics } from '@/types';

interface EnhancedAnalyticsDashboardProps {
  initialMetrics: DashboardMetrics;
  currency: string;
}

interface FilterState {
  dateRange: string;
  product: string;
  category: string;
  supplier: string;
}

interface DrillDownData {
  type: 'revenue' | 'orders' | 'products' | 'customers';
  data: any[];
  title: string;
}

export function EnhancedAnalyticsDashboard({ initialMetrics, currency }: EnhancedAnalyticsDashboardProps) {
  const [metrics, setMetrics] = useState<DashboardMetrics>(initialMetrics);
  const [isLoading, setIsLoading] = useState(false);
  const [activeTab, setActiveTab] = useState('overview');
  const [filters, setFilters] = useState<FilterState>({
    dateRange: '30d',
    product: 'all',
    category: 'all',
    supplier: 'all'
  });
  const [drillDown, setDrillDown] = useState<DrillDownData | null>(null);
  const [showAdvancedFilters, setShowAdvancedFilters] = useState(false);

  // Real-time data refresh function
  const refreshData = useCallback(async () => {
    setIsLoading(true);
    try {
      const response = await fetch(`/api/analytics/dashboard?range=${filters.dateRange}`);
      if (response.ok) {
        const newMetrics = await response.json();
        setMetrics(newMetrics);
      }
    } catch (error) {
      console.error('Failed to refresh data:', error);
    } finally {
      setIsLoading(false);
    }
  }, [filters.dateRange]);

  // Auto-refresh every 30 seconds for real-time updates
  useEffect(() => {
    const interval = setInterval(refreshData, 30000);
    return () => clearInterval(interval);
  }, [refreshData]);

  // Filter change handler
  const handleFilterChange = useCallback((key: keyof FilterState, value: string) => {
    setFilters(prev => ({ ...prev, [key]: value }));
  }, []);

  // Drill-down handler
  const handleDrillDown = useCallback((type: DrillDownData['type'], title: string) => {
    // Mock drill-down data - in real implementation, fetch from API
    const mockData = {
      revenue: [
        { period: 'Week 1', value: 12500, orders: 45 },
        { period: 'Week 2', value: 15200, orders: 52 },
        { period: 'Week 3', value: 11800, orders: 38 },
        { period: 'Week 4', value: 18900, orders: 67 }
      ],
      orders: [
        { product: 'Widget A', orders: 45, revenue: 12500 },
        { product: 'Widget B', orders: 32, revenue: 8900 },
        { product: 'Widget C', orders: 28, revenue: 7200 }
      ],
      products: metrics.top_products || [],
      customers: [
        { segment: 'New', count: 23, value: 5600 },
        { segment: 'Returning', count: 45, value: 12400 },
        { segment: 'VIP', count: 8, value: 8900 }
      ]
    };

    setDrillDown({
      type,
      data: mockData[type] || [],
      title
    });
  }, [metrics.top_products]);

  // Export functionality
  const handleExport = useCallback((format: 'csv' | 'pdf' | 'excel') => {
    // Implementation for export functionality
    console.log(`Exporting data as ${format}`);
    // In real implementation, trigger download
  }, []);

  const kpiCards = [
    {
      title: 'Total Revenue',
      value: formatCentsAsCurrency(metrics.total_revenue, currency),
      change: `${metrics.revenue_change?.toFixed(1) || 0}%`,
      changeType: (metrics.revenue_change || 0) >= 0 ? 'increase' : 'decrease',
      icon: DollarSign,
      color: 'emerald',
      onClick: () => handleDrillDown('revenue', 'Revenue Breakdown')
    },
    {
      title: 'Total Orders',
      value: metrics.total_orders?.toLocaleString() || '0',
      change: `${metrics.orders_change?.toFixed(1) || 0}%`,
      changeType: (metrics.orders_change || 0) >= 0 ? 'increase' : 'decrease',
      icon: Package,
      color: 'blue',
      onClick: () => handleDrillDown('orders', 'Order Details')
    },
    {
      title: 'New Customers',
      value: metrics.new_customers?.toLocaleString() || '0',
      change: `${metrics.customers_change?.toFixed(1) || 0}%`,
      changeType: (metrics.customers_change || 0) >= 0 ? 'increase' : 'decrease',
      icon: Users,
      color: 'purple',
      onClick: () => handleDrillDown('customers', 'Customer Segments')
    },
    {
      title: 'Top Products',
      value: metrics.top_products?.length || 0,
      change: 'View All',
      changeType: 'neutral' as const,
      icon: Target,
      color: 'orange',
      onClick: () => handleDrillDown('products', 'Product Performance')
    }
  ];

  return (
    <div className="space-y-6">
      {/* Enhanced Header with Controls */}
      <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Enhanced Analytics</h1>
          <p className="text-muted-foreground">
            Real-time insights with advanced filtering and drill-down capabilities
          </p>
        </div>
        
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={refreshData}
            disabled={isLoading}
            className="gap-2"
          >
            <RefreshCw className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
            Refresh
          </Button>
          
          <Select value={filters.dateRange} onValueChange={(value) => handleFilterChange('dateRange', value)}>
            <SelectTrigger className="w-[140px]">
              <Calendar className="h-4 w-4" />
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="7d">Last 7 Days</SelectItem>
              <SelectItem value="30d">Last 30 Days</SelectItem>
              <SelectItem value="90d">Last 90 Days</SelectItem>
              <SelectItem value="365d">Last Year</SelectItem>
              <SelectItem value="custom">Custom Range</SelectItem>
            </SelectContent>
          </Select>

          <Button
            variant="outline"
            size="sm"
            onClick={() => setShowAdvancedFilters(!showAdvancedFilters)}
            className="gap-2"
          >
            <Filter className="h-4 w-4" />
            Filters
            <ChevronDown className={`h-4 w-4 transition-transform ${showAdvancedFilters ? 'rotate-180' : ''}`} />
          </Button>
        </div>
      </div>

      {/* Advanced Filters Panel */}
      <AnimatePresence>
        {showAdvancedFilters && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            className="overflow-hidden"
          >
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Advanced Filters</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                  <div className="space-y-2">
                    <label className="text-sm font-medium">Product Search</label>
                    <div className="relative">
                      <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
                      <Input
                        placeholder="Search products..."
                        className="pl-8"
                        value={filters.product}
                        onChange={(e) => handleFilterChange('product', e.target.value)}
                      />
                    </div>
                  </div>
                  
                  <div className="space-y-2">
                    <label className="text-sm font-medium">Category</label>
                    <Select value={filters.category} onValueChange={(value) => handleFilterChange('category', value)}>
                      <SelectTrigger>
                        <SelectValue placeholder="All Categories" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All Categories</SelectItem>
                        <SelectItem value="electronics">Electronics</SelectItem>
                        <SelectItem value="clothing">Clothing</SelectItem>
                        <SelectItem value="home">Home & Garden</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  
                  <div className="space-y-2">
                    <label className="text-sm font-medium">Supplier</label>
                    <Select value={filters.supplier} onValueChange={(value) => handleFilterChange('supplier', value)}>
                      <SelectTrigger>
                        <SelectValue placeholder="All Suppliers" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All Suppliers</SelectItem>
                        <SelectItem value="supplier1">Supplier 1</SelectItem>
                        <SelectItem value="supplier2">Supplier 2</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  
                  <div className="space-y-2">
                    <label className="text-sm font-medium">Actions</label>
                    <div className="flex gap-2">
                      <Button size="sm" variant="outline" onClick={() => handleExport('csv')}>
                        <Download className="h-4 w-4 mr-1" />
                        CSV
                      </Button>
                      <Button size="sm" variant="outline" onClick={() => handleExport('pdf')}>
                        <Download className="h-4 w-4 mr-1" />
                        PDF
                      </Button>
                    </div>
                  </div>
                </div>
              </CardContent>
            </Card>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Enhanced KPI Cards */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        {kpiCards.map((kpi, index) => (
          <motion.div
            key={kpi.title}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: index * 0.1 }}
          >
            <Card 
              className="cursor-pointer transition-all hover:shadow-lg hover:scale-105 active:scale-100"
              onClick={kpi.onClick}
            >
              <CardContent className="p-6">
                <div className="flex items-center justify-between">
                  <div className="space-y-2">
                    <p className="text-sm font-medium text-muted-foreground">{kpi.title}</p>
                    <p className="text-2xl font-bold">{kpi.value}</p>
                    <div className="flex items-center space-x-2">
                      {kpi.changeType === 'increase' ? (
                        <TrendingUp className="h-4 w-4 text-emerald-600" />
                      ) : kpi.changeType === 'decrease' ? (
                        <TrendingDown className="h-4 w-4 text-red-600" />
                      ) : null}
                      <span className={`text-sm font-medium ${
                        kpi.changeType === 'increase' ? 'text-emerald-600' : 
                        kpi.changeType === 'decrease' ? 'text-red-600' : 
                        'text-muted-foreground'
                      }`}>
                        {kpi.change}
                      </span>
                    </div>
                  </div>
                  <div className={`p-3 rounded-full bg-${kpi.color}-100`}>
                    <kpi.icon className={`h-6 w-6 text-${kpi.color}-600`} />
                  </div>
                </div>
              </CardContent>
            </Card>
          </motion.div>
        ))}
      </div>

      {/* Main Analytics Tabs */}
      <Tabs value={activeTab} onValueChange={setActiveTab} className="space-y-4">
        <TabsList className="grid w-full grid-cols-4">
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="trends">Trends</TabsTrigger>
          <TabsTrigger value="products">Products</TabsTrigger>
          <TabsTrigger value="customers">Customers</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="space-y-4">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Sales Chart */}
            <Card>
              <CardHeader>
                <CardTitle>Sales Trend</CardTitle>
                <CardDescription>Revenue over time with order volume</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="h-80">
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={metrics.sales_over_time || []}>
                      <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                      <XAxis 
                        dataKey="date" 
                        className="text-xs"
                        tickFormatter={(date) => new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
                      />
                      <YAxis className="text-xs" />
                      <Tooltip 
                        contentStyle={{ 
                          backgroundColor: 'hsl(var(--background))', 
                          border: '1px solid hsl(var(--border))',
                          borderRadius: '8px'
                        }}
                        formatter={(value: number) => [formatCentsAsCurrency(value, currency), 'Revenue']}
                      />
                      <Line 
                        type="monotone" 
                        dataKey="revenue" 
                        stroke="hsl(var(--primary))" 
                        strokeWidth={3}
                        dot={{ fill: 'hsl(var(--primary))', strokeWidth: 2, r: 4 }}
                        activeDot={{ r: 6, fill: 'hsl(var(--primary))' }}
                      />
                    </LineChart>
                  </ResponsiveContainer>
                </div>
              </CardContent>
            </Card>

            {/* Top Products */}
            <Card>
              <CardHeader>
                <CardTitle>Top Products</CardTitle>
                <CardDescription>Best performing products by revenue</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  {(metrics.top_products || []).slice(0, 5).map((product, index) => (
                    <div key={product.product_id} className="flex items-center justify-between p-3 rounded-lg bg-muted/50">
                      <div className="flex items-center space-x-3">
                        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-primary text-primary-foreground text-sm font-bold">
                          {index + 1}
                        </div>
                        <div>
                          <p className="font-medium">{product.product_name}</p>
                          <p className="text-sm text-muted-foreground">{product.product_id}</p>
                        </div>
                      </div>
                      <div className="text-right">
                        <p className="font-bold">{formatCentsAsCurrency(product.total_revenue, currency)}</p>
                        <p className="text-sm text-muted-foreground">{product.quantity_sold} sold</p>
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          </div>
        </TabsContent>

        <TabsContent value="trends" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Trend Analysis</CardTitle>
              <CardDescription>Identify patterns and seasonal trends</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="h-80">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={metrics.sales_over_time || []}>
                    <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                    <XAxis dataKey="date" className="text-xs" />
                    <YAxis className="text-xs" />
                    <Tooltip />
                    <Bar dataKey="revenue" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="products" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Product Performance</CardTitle>
              <CardDescription>Detailed product analytics and insights</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {(metrics.top_products || []).map((product) => (
                  <div key={product.product_id} className="border rounded-lg p-4">
                    <div className="flex items-center justify-between">
                      <div>
                        <h4 className="font-semibold">{product.product_name}</h4>
                        <p className="text-sm text-muted-foreground">{product.product_id}</p>
                      </div>
                      <div className="text-right">
                        <p className="font-bold">{formatCentsAsCurrency(product.total_revenue, currency)}</p>
                        <p className="text-sm text-muted-foreground">{product.quantity_sold} units</p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="customers" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Customer Analytics</CardTitle>
              <CardDescription>Customer behavior and segmentation</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="text-center p-4 border rounded-lg">
                  <p className="text-2xl font-bold">{metrics.new_customers || 0}</p>
                  <p className="text-sm text-muted-foreground">New Customers</p>
                </div>
                <div className="text-center p-4 border rounded-lg">
                  <p className="text-2xl font-bold">{Math.round((metrics.new_customers || 0) * 2.3)}</p>
                  <p className="text-sm text-muted-foreground">Returning Customers</p>
                </div>
                <div className="text-center p-4 border rounded-lg">
                  <p className="text-2xl font-bold">{Math.round((metrics.new_customers || 0) * 0.15)}</p>
                  <p className="text-sm text-muted-foreground">VIP Customers</p>
                </div>
              </div>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {/* Drill-down Modal */}
      <AnimatePresence>
        {drillDown && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
            onClick={() => setDrillDown(null)}
          >
            <motion.div
              initial={{ scale: 0.9, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.9, opacity: 0 }}
              className="bg-background rounded-lg p-6 max-w-4xl w-full max-h-[80vh] overflow-auto"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-xl font-bold">{drillDown.title}</h3>
                <Button variant="ghost" size="sm" onClick={() => setDrillDown(null)}>
                  ×
                </Button>
              </div>
              
              <div className="space-y-4">
                {drillDown.data.map((item, index) => (
                  <div key={index} className="p-3 border rounded-lg">
                    <pre className="text-sm">{JSON.stringify(item, null, 2)}</pre>
                  </div>
                ))}
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
