'use client';

import React, { useState, useEffect } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Alert, AlertDescription } from '@/components/ui/alert';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  ResponsiveContainer
} from 'recharts';
import {
  TrendingUp, DollarSign, Package,
  Brain, Lightbulb, Target, AlertTriangle, CheckCircle
} from 'lucide-react';

interface AdvancedAnalyticsProps {
  companyId: string;
}

interface AnalyticsData {
  bundles?: any;
  economicImpact?: any;
  descriptions?: any;
  bundleAnalysis?: any;
  economicAnalysis?: any;
  combinedInsights?: {
    totalRevenueOpportunity?: number;
    strategicRecommendations?: string[];
    riskAssessment?: any;
  };
}

const COLORS = {
  primary: '#3b82f6',
  success: '#10b981',
  warning: '#f59e0b',
  danger: '#ef4444',
  purple: '#8b5cf6',
  indigo: '#6366f1'
};

export function AdvancedAnalyticsDashboard({ companyId }: AdvancedAnalyticsProps) {
  const [activeTab, setActiveTab] = useState('overview');
  const [analyticsData, setAnalyticsData] = useState<AnalyticsData>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchAnalytics = async (type: string) => {
    try {
      setLoading(true);
      setError(null);
      
      const response = await fetch(`/api/ai-analytics?type=${type}&format=json`);
      
      if (!response.ok) {
        throw new Error(`Failed to fetch ${type} analytics`);
      }
      
      const result = await response.json();
      
      setAnalyticsData(prev => ({
        ...prev,
        [type.replace('-', '_')]: result.data
      }));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch analytics');
    } finally {
      setLoading(false);
    }
  };

  const fetchBatchAnalytics = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const response = await fetch('/api/ai-analytics', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          analysisType: 'batch-analysis',
          parameters: {
            bundleCount: 5,
            economicScenario: 'pricing_optimization',
            economicParameters: { priceChangePercent: 10 }
          }
        })
      });
      
      if (!response.ok) {
        throw new Error('Failed to fetch batch analytics');
      }
      
      const result = await response.json();
      setAnalyticsData(result.data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch analytics');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchBatchAnalytics();
  }, [companyId]);

  const renderBundleAnalysis = () => {
    const bundleData = analyticsData.bundleAnalysis;
    if (!bundleData) return <div>Loading bundle analysis...</div>;

    return (
      <div className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Bundle Suggestions</CardTitle>
              <Package className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{bundleData.suggestions?.length || 0}</div>
              <p className="text-xs text-muted-foreground">AI-generated bundles</p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Revenue Potential</CardTitle>
              <DollarSign className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">
                ${(bundleData.totalPotentialRevenue || 0).toLocaleString()}
              </div>
              <p className="text-xs text-muted-foreground">Monthly potential</p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Implementation Tips</CardTitle>
              <Lightbulb className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">
                {bundleData.implementationRecommendations?.length || 0}
              </div>
              <p className="text-xs text-muted-foreground">Actionable recommendations</p>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Bundle Performance Projections</CardTitle>
            <CardDescription>Expected demand and revenue by bundle</CardDescription>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={bundleData.suggestions?.slice(0, 5) || []}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="bundleName" />
                <YAxis yAxisId="left" />
                <YAxis yAxisId="right" orientation="right" />
                <Tooltip />
                <Legend />
                <Bar yAxisId="left" dataKey="estimatedDemand" fill={COLORS.primary} name="Estimated Demand" />
                <Bar yAxisId="right" dataKey="suggestedPrice" fill={COLORS.success} name="Suggested Price ($)" />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {bundleData.suggestions?.slice(0, 4).map((bundle: any, index: number) => (
            <Card key={index}>
              <CardHeader>
                <CardTitle className="flex items-center justify-between">
                  {bundle.bundleName}
                  <Badge variant="secondary">${bundle.suggestedPrice}</Badge>
                </CardTitle>
                <CardDescription>{bundle.reasoning}</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="space-y-2">
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Profit Margin:</span>
                    <span className="font-medium">{bundle.profitMargin}%</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Cross-sell Opportunity:</span>
                    <span className="font-medium">+{bundle.crossSellOpportunity}%</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm text-muted-foreground">Target Segment:</span>
                    <span className="font-medium">{bundle.targetCustomerSegment}</span>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    );
  };

  const renderEconomicAnalysis = () => {
    const economicData = analyticsData.economicAnalysis;
    if (!economicData) return <div>Loading economic analysis...</div>;

    const analysis = economicData.analysis;
    const revenueData = [
      { name: 'Current', value: analysis?.revenueImpact?.currentRevenue || 0 },
      { name: 'Projected', value: analysis?.revenueImpact?.projectedRevenue || 0 }
    ];

    const profitData = [
      { name: 'Current', value: analysis?.profitabilityImpact?.currentProfit || 0 },
      { name: 'Projected', value: analysis?.profitabilityImpact?.projectedProfit || 0 }
    ];

    return (
      <div className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Revenue Impact</CardTitle>
              <TrendingUp className="h-4 w-4 text-green-600" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">
                +{analysis?.revenueImpact?.revenueChangePercent || 0}%
              </div>
              <p className="text-xs text-muted-foreground">
                ${(analysis?.revenueImpact?.revenueChange || 0).toLocaleString()} increase
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Profit Impact</CardTitle>
              <DollarSign className="h-4 w-4 text-green-600" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">
                +{analysis?.profitabilityImpact?.profitChangePercent || 0}%
              </div>
              <p className="text-xs text-muted-foreground">
                ${(analysis?.profitabilityImpact?.profitChange || 0).toLocaleString()} increase
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Risk Level</CardTitle>
              <AlertTriangle className={`h-4 w-4 ${
                analysis?.riskAssessment?.riskLevel === 'low' ? 'text-green-600' :
                analysis?.riskAssessment?.riskLevel === 'medium' ? 'text-yellow-600' :
                'text-red-600'
              }`} />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold capitalize">
                {analysis?.riskAssessment?.riskLevel || 'Unknown'}
              </div>
              <p className="text-xs text-muted-foreground">Overall assessment</p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Confidence</CardTitle>
              <Target className="h-4 w-4 text-blue-600" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{analysis?.confidence || 0}%</div>
              <p className="text-xs text-muted-foreground">Analysis confidence</p>
            </CardContent>
          </Card>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <Card>
            <CardHeader>
              <CardTitle>Revenue Comparison</CardTitle>
              <CardDescription>Current vs. projected monthly revenue</CardDescription>
            </CardHeader>
            <CardContent>
              <ResponsiveContainer width="100%" height={250}>
                <BarChart data={revenueData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="name" />
                  <YAxis />
                  <Tooltip />
                  <Bar dataKey="value" fill={COLORS.primary} />
                </BarChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Profit Comparison</CardTitle>
              <CardDescription>Current vs. projected monthly profit</CardDescription>
            </CardHeader>
            <CardContent>
              <ResponsiveContainer width="100%" height={250}>
                <BarChart data={profitData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="name" />
                  <YAxis />
                  <Tooltip />
                  <Bar dataKey="value" fill={COLORS.success} />
                </BarChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Strategic Recommendations</CardTitle>
            <CardDescription>AI-powered implementation strategy</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {analysis?.recommendations?.map((rec: string, index: number) => (
                <div key={index} className="flex items-start gap-2">
                  <CheckCircle className="h-4 w-4 text-green-600 mt-0.5 flex-shrink-0" />
                  <span className="text-sm">{rec}</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>
    );
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">Advanced Analytics</h1>
          <p className="text-muted-foreground">
            AI-powered business intelligence and strategic insights
          </p>
        </div>
        <div className="flex gap-2">
          <Button 
            onClick={() => fetchAnalytics('bundle-suggestions')}
            disabled={loading}
            variant="outline"
          >
            Refresh Bundles
          </Button>
          <Button 
            onClick={() => fetchAnalytics('economic-impact')}
            disabled={loading}
            variant="outline"
          >
            Update Economic Analysis
          </Button>
        </div>
      </div>

      {error && (
        <Alert variant="destructive">
          <AlertTriangle className="h-4 w-4" />
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
        <TabsList className="grid w-full grid-cols-3">
          <TabsTrigger value="overview" className="flex items-center gap-2">
            <Brain className="h-4 w-4" />
            Overview
          </TabsTrigger>
          <TabsTrigger value="bundles" className="flex items-center gap-2">
            <Package className="h-4 w-4" />
            Bundle Analysis
          </TabsTrigger>
          <TabsTrigger value="economic" className="flex items-center gap-2">
            <TrendingUp className="h-4 w-4" />
            Economic Impact
          </TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Total Revenue Opportunity</CardTitle>
                <DollarSign className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">
                  ${(analyticsData.combinedInsights?.totalRevenueOpportunity || 0).toLocaleString()}
                </div>
                <p className="text-xs text-muted-foreground">Combined potential</p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Active Insights</CardTitle>
                <Brain className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">
                  {(analyticsData.combinedInsights?.strategicRecommendations?.length || 0)}
                </div>
                <p className="text-xs text-muted-foreground">Actionable recommendations</p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Bundle Opportunities</CardTitle>
                <Package className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">
                  {analyticsData.bundleAnalysis?.suggestions?.length || 0}
                </div>
                <p className="text-xs text-muted-foreground">AI-suggested bundles</p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Analysis Status</CardTitle>
                <CheckCircle className="h-4 w-4 text-green-600" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">Active</div>
                <p className="text-xs text-muted-foreground">Real-time insights</p>
              </CardContent>
            </Card>
          </div>

          <Card>
            <CardHeader>
              <CardTitle>Strategic Recommendations</CardTitle>
              <CardDescription>Combined insights from all analyses</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {analyticsData.combinedInsights?.strategicRecommendations?.slice(0, 6).map((rec: string, index: number) => (
                  <div key={index} className="flex items-start gap-2 p-3 bg-muted rounded-lg">
                    <Lightbulb className="h-4 w-4 text-yellow-600 mt-0.5 flex-shrink-0" />
                    <span className="text-sm">{rec}</span>
                  </div>
                )) || (
                  <div className="col-span-2 text-center text-muted-foreground py-8">
                    Run analytics to see strategic recommendations
                  </div>
                )}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="bundles" className="space-y-6">
          {renderBundleAnalysis()}
        </TabsContent>

        <TabsContent value="economic" className="space-y-6">
          {renderEconomicAnalysis()}
        </TabsContent>
      </Tabs>
    </div>
  );
}
