'use client';

import React, { useState, useEffect } from 'react';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from '@/components/ui/tabs';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import {
  LineChart,
  Line,
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer
} from 'recharts';
import {
  TrendingUp,
  TrendingDown,
  Minus,
  AlertTriangle,
  Target,
  Package,
  BarChart3,
  Zap,
  Lightbulb,
  Shield
} from 'lucide-react';

// Types from the enhanced forecasting service
interface EnhancedForecast {
  sku: string;
  productName: string;
  forecastPeriodDays: number;
  predictions: {
    daily: number[];
    weekly: number[];
    monthly: number[];
  };
  seasonalPatterns: Array<{
    month: number;
    seasonalityFactor: number;
    historicalAverage: number;
    confidence: number;
  }>;
  modelUsed: {
    name: string;
    algorithm: string;
    accuracy: number;
    confidence: number;
  };
  inventoryOptimization: {
    currentStock: number;
    recommendedReorderPoint: number;
    recommendedReorderQuantity: number;
    safetyStockDays: number;
    stockoutRisk: 'low' | 'medium' | 'high';
    expectedDepleteDate: string | null;
  };
  businessInsights: {
    trend: 'increasing' | 'decreasing' | 'stable' | 'volatile';
    seasonality: 'high' | 'medium' | 'low' | 'none';
    riskFactors: string[];
    opportunities: string[];
    recommendations: string[];
  };
  confidence: number;
  lastUpdated: string;
}

interface CompanyForecastSummary {
  companyId: string;
  totalProducts: number;
  forecastAccuracy: number;
  topRisks: Array<{
    sku: string;
    productName: string;
    risk: string;
    severity: 'high' | 'medium' | 'low';
  }>;
  topOpportunities: Array<{
    sku: string;
    productName: string;
    opportunity: string;
    potential: number;
  }>;
  overallTrend: 'growth' | 'decline' | 'stable';
  seasonalInsights: string[];
  lastAnalyzed: string;
}

export default function EnhancedForecastingDashboard() {
  const [selectedSku, setSelectedSku] = useState<string>('');
  const [forecastDays, setForecastDays] = useState<number>(90);
  const [forecast, setForecast] = useState<EnhancedForecast | null>(null);
  const [companySummary, setCompanySummary] = useState<CompanyForecastSummary | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load company summary on component mount
  useEffect(() => {
    loadCompanySummary();
  }, []);

  const loadCompanySummary = async () => {
    try {
      setLoading(true);
      const response = await fetch('/api/analytics/forecast-summary');
      if (!response.ok) throw new Error('Failed to load forecast summary');
      
      const data = await response.json();
      setCompanySummary(data.data);
    } catch (err) {
      setError('Failed to load company forecast summary');
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const generateForecast = async () => {
    if (!selectedSku) {
      setError('Please enter a SKU');
      return;
    }

    try {
      setLoading(true);
      setError(null);
      
      const response = await fetch(
        `/api/analytics/enhanced-forecast?sku=${encodeURIComponent(selectedSku)}&forecastDays=${forecastDays}`
      );
      
      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || 'Failed to generate forecast');
      }
      
      const data = await response.json();
      setForecast(data.data);
    } catch (err: any) {
      setError(err.message);
      console.error('Forecast generation error:', err);
    } finally {
      setLoading(false);
    }
  };

  const getTrendIcon = (trend: string) => {
    switch (trend) {
      case 'increasing': return <TrendingUp className="h-4 w-4 text-green-500" />;
      case 'decreasing': return <TrendingDown className="h-4 w-4 text-red-500" />;
      case 'stable': return <Minus className="h-4 w-4 text-blue-500" />;
      default: return <BarChart3 className="h-4 w-4 text-gray-500" />;
    }
  };

  const getRiskColor = (risk: string) => {
    switch (risk) {
      case 'high': return 'destructive';
      case 'medium': return 'default';
      case 'low': return 'secondary';
      default: return 'outline';
    }
  };

  const formatChartData = (data: number[], type: 'daily' | 'weekly' | 'monthly') => {
    return data.map((value, index) => ({
      period: type === 'daily' ? `Day ${index + 1}` :
               type === 'weekly' ? `Week ${index + 1}` : 
               `Month ${index + 1}`,
      value: Math.round(value * 100) / 100,
      index
    }));
  };

  return (
    <div className="container mx-auto p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Enhanced Demand Forecasting</h1>
          <p className="text-muted-foreground mt-2">
            Machine learning-powered demand forecasting with seasonal patterns and inventory optimization
          </p>
        </div>
        <div className="flex items-center space-x-2">
          <Zap className="h-5 w-5 text-amber-500" />
          <span className="text-sm font-medium">ML-Powered</span>
        </div>
      </div>

      {/* Forecast Input */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center space-x-2">
            <Target className="h-5 w-5" />
            <span>Generate Product Forecast</span>
          </CardTitle>
          <CardDescription>
            Enter a product SKU to generate an enhanced demand forecast with ML insights
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex space-x-4">
            <div className="flex-1">
              <Label htmlFor="sku">Product SKU</Label>
              <Input
                id="sku"
                placeholder="Enter product SKU..."
                value={selectedSku}
                onChange={(e) => setSelectedSku(e.target.value)}
              />
            </div>
            <div className="w-48">
              <Label htmlFor="forecastDays">Forecast Period</Label>
              <Select value={forecastDays.toString()} onValueChange={(value) => setForecastDays(parseInt(value))}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="30">30 Days</SelectItem>
                  <SelectItem value="60">60 Days</SelectItem>
                  <SelectItem value="90">90 Days</SelectItem>
                  <SelectItem value="180">180 Days</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex items-end">
              <Button onClick={generateForecast} disabled={loading}>
                {loading ? 'Generating...' : 'Generate Forecast'}
              </Button>
            </div>
          </div>
          
          {error && (
            <Alert variant="destructive">
              <AlertTriangle className="h-4 w-4" />
              <AlertTitle>Error</AlertTitle>
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>

      {/* Company Summary */}
      {companySummary && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <Card>
            <CardContent className="p-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm font-medium text-muted-foreground">Products Analyzed</p>
                  <p className="text-2xl font-bold">{companySummary.totalProducts}</p>
                </div>
                <Package className="h-8 w-8 text-muted-foreground" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm font-medium text-muted-foreground">Forecast Accuracy</p>
                  <p className="text-2xl font-bold">{Math.round(companySummary.forecastAccuracy * 100)}%</p>
                </div>
                <Target className="h-8 w-8 text-muted-foreground" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm font-medium text-muted-foreground">Overall Trend</p>
                  <div className="flex items-center space-x-1">
                    {getTrendIcon(companySummary.overallTrend)}
                    <p className="text-2xl font-bold capitalize">{companySummary.overallTrend}</p>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm font-medium text-muted-foreground">High Risk Items</p>
                  <p className="text-2xl font-bold text-red-500">
                    {companySummary.topRisks.filter(r => r.severity === 'high').length}
                  </p>
                </div>
                <AlertTriangle className="h-8 w-8 text-red-500" />
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      {/* Forecast Results */}
      {forecast && (
        <div className="space-y-6">
          {/* Model Information and Key Metrics */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Model Information</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-2">
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Algorithm:</span>
                    <Badge variant="outline">{forecast.modelUsed.algorithm}</Badge>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Confidence:</span>
                    <span className="font-medium">{Math.round(forecast.confidence * 100)}%</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Trend:</span>
                    <div className="flex items-center space-x-1">
                      {getTrendIcon(forecast.businessInsights.trend)}
                      <span className="capitalize text-sm">{forecast.businessInsights.trend}</span>
                    </div>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Seasonality:</span>
                    <Badge variant={forecast.businessInsights.seasonality === 'high' ? 'default' : 'secondary'}>
                      {forecast.businessInsights.seasonality}
                    </Badge>
                  </div>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Inventory Status</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-2">
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Current Stock:</span>
                    <span className="font-medium">{forecast.inventoryOptimization.currentStock}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Stockout Risk:</span>
                    <Badge variant={getRiskColor(forecast.inventoryOptimization.stockoutRisk) as any}>
                      {forecast.inventoryOptimization.stockoutRisk}
                    </Badge>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Reorder Point:</span>
                    <span className="font-medium">{Math.round(forecast.inventoryOptimization.recommendedReorderPoint)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Reorder Qty:</span>
                    <span className="font-medium">{Math.round(forecast.inventoryOptimization.recommendedReorderQuantity)}</span>
                  </div>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Key Predictions</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-2">
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Next 30 Days:</span>
                    <span className="font-medium">
                      {Math.round(forecast.predictions.daily.slice(0, 30).reduce((sum, val) => sum + val, 0))} units
                    </span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Next Week:</span>
                    <span className="font-medium">
                      {Math.round(forecast.predictions.daily.slice(0, 7).reduce((sum, val) => sum + val, 0))} units
                    </span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Expected Depletion:</span>
                    <span className="text-sm">
                      {forecast.inventoryOptimization.expectedDepleteDate 
                        ? new Date(forecast.inventoryOptimization.expectedDepleteDate).toLocaleDateString()
                        : 'No risk'
                      }
                    </span>
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>

          {/* Charts and Insights */}
          <Tabs defaultValue="forecast" className="space-y-4">
            <TabsList>
              <TabsTrigger value="forecast">Forecast Charts</TabsTrigger>
              <TabsTrigger value="seasonal">Seasonal Patterns</TabsTrigger>
              <TabsTrigger value="insights">Business Insights</TabsTrigger>
            </TabsList>

            <TabsContent value="forecast" className="space-y-4">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <Card>
                  <CardHeader>
                    <CardTitle>Daily Forecast (Next 30 Days)</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <ResponsiveContainer width="100%" height={300}>
                      <LineChart data={formatChartData(forecast.predictions.daily.slice(0, 30), 'daily')}>
                        <CartesianGrid strokeDasharray="3 3" />
                        <XAxis dataKey="period" />
                        <YAxis />
                        <Tooltip />
                        <Line type="monotone" dataKey="value" stroke="#8884d8" strokeWidth={2} />
                      </LineChart>
                    </ResponsiveContainer>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle>Weekly Forecast</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <ResponsiveContainer width="100%" height={300}>
                      <AreaChart data={formatChartData(forecast.predictions.weekly.slice(0, 12), 'weekly')}>
                        <CartesianGrid strokeDasharray="3 3" />
                        <XAxis dataKey="period" />
                        <YAxis />
                        <Tooltip />
                        <Area type="monotone" dataKey="value" stroke="#82ca9d" fill="#82ca9d" fillOpacity={0.6} />
                      </AreaChart>
                    </ResponsiveContainer>
                  </CardContent>
                </Card>
              </div>

              <Card>
                <CardHeader>
                  <CardTitle>Monthly Forecast Comparison</CardTitle>
                </CardHeader>
                <CardContent>
                  <ResponsiveContainer width="100%" height={400}>
                    <BarChart data={formatChartData(forecast.predictions.monthly.slice(0, 6), 'monthly')}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="period" />
                      <YAxis />
                      <Tooltip />
                      <Bar dataKey="value" fill="#8884d8" />
                    </BarChart>
                  </ResponsiveContainer>
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="seasonal" className="space-y-4">
              <Card>
                <CardHeader>
                  <CardTitle>Seasonal Patterns by Month</CardTitle>
                  <CardDescription>
                    Historical seasonal factors showing demand variations throughout the year
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <ResponsiveContainer width="100%" height={400}>
                    <BarChart data={forecast.seasonalPatterns.map(p => ({
                      month: new Date(2024, p.month - 1).toLocaleString('default', { month: 'short' }),
                      factor: Math.round(p.seasonalityFactor * 100) / 100,
                      confidence: Math.round(p.confidence * 100)
                    }))}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="month" />
                      <YAxis />
                      <Tooltip />
                      <Bar dataKey="factor" fill="#82ca9d" />
                    </BarChart>
                  </ResponsiveContainer>
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="insights" className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {/* Risk Factors */}
                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center space-x-2">
                      <Shield className="h-5 w-5 text-red-500" />
                      <span>Risk Factors</span>
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    {forecast.businessInsights.riskFactors.length > 0 ? (
                      <ul className="space-y-2">
                        {forecast.businessInsights.riskFactors.map((risk, index) => (
                          <li key={index} className="flex items-start space-x-2">
                            <AlertTriangle className="h-4 w-4 text-red-500 mt-0.5" />
                            <span className="text-sm">{risk}</span>
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <p className="text-sm text-muted-foreground">No significant risk factors identified</p>
                    )}
                  </CardContent>
                </Card>

                {/* Opportunities */}
                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center space-x-2">
                      <Lightbulb className="h-5 w-5 text-yellow-500" />
                      <span>Opportunities</span>
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    {forecast.businessInsights.opportunities.length > 0 ? (
                      <ul className="space-y-2">
                        {forecast.businessInsights.opportunities.map((opportunity, index) => (
                          <li key={index} className="flex items-start space-x-2">
                            <Lightbulb className="h-4 w-4 text-yellow-500 mt-0.5" />
                            <span className="text-sm">{opportunity}</span>
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <p className="text-sm text-muted-foreground">No specific opportunities identified</p>
                    )}
                  </CardContent>
                </Card>
              </div>

              {/* Recommendations */}
              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center space-x-2">
                    <Target className="h-5 w-5 text-blue-500" />
                    <span>Recommendations</span>
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  {forecast.businessInsights.recommendations.length > 0 ? (
                    <ul className="space-y-3">
                      {forecast.businessInsights.recommendations.map((recommendation, index) => (
                        <li key={index} className="flex items-start space-x-2">
                          <Target className="h-4 w-4 text-blue-500 mt-0.5" />
                          <span className="text-sm">{recommendation}</span>
                        </li>
                      ))}
                    </ul>
                  ) : (
                    <p className="text-sm text-muted-foreground">No specific recommendations at this time</p>
                  )}
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        </div>
      )}

      {/* Company Risks and Opportunities */}
      {companySummary && companySummary.topRisks.length > 0 && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center space-x-2">
                <AlertTriangle className="h-5 w-5 text-red-500" />
                <span>Top Risk Products</span>
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                {companySummary.topRisks.slice(0, 5).map((risk, index) => (
                  <div key={index} className="flex items-center justify-between p-3 border rounded-lg">
                    <div className="flex-1">
                      <p className="font-medium text-sm">{risk.productName}</p>
                      <p className="text-xs text-muted-foreground">{risk.sku}</p>
                      <p className="text-xs text-red-600">{risk.risk}</p>
                    </div>
                    <Badge variant={getRiskColor(risk.severity) as any}>
                      {risk.severity}
                    </Badge>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center space-x-2">
                <Lightbulb className="h-5 w-5 text-yellow-500" />
                <span>Top Opportunities</span>
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                {companySummary.topOpportunities.slice(0, 5).map((opportunity, index) => (
                  <div key={index} className="flex items-center justify-between p-3 border rounded-lg">
                    <div className="flex-1">
                      <p className="font-medium text-sm">{opportunity.productName}</p>
                      <p className="text-xs text-muted-foreground">{opportunity.sku}</p>
                      <p className="text-xs text-green-600">{opportunity.opportunity}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-sm font-medium">{Math.round(opportunity.potential)} units</p>
                      <p className="text-xs text-muted-foreground">potential</p>
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
