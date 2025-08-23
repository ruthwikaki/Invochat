'use client';

import { useEffect, useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Progress } from '@/components/ui/progress';
import { Loader2, AlertTriangle, Star, Target, DollarSign } from 'lucide-react';
import { formatCentsAsCurrency } from '@/lib/utils';

interface ABCProduct {
    sku: string;
    product_name: string;
    category: 'A' | 'B' | 'C';
    priority: string;
    composite_score: number;
    revenue: number;
    revenue_contribution: number;
    revenue_rank: number;
    margin: number;
    margin_percentage: number;
    margin_contribution: number;
    margin_rank: number;
    velocity: number;
    velocity_rank: number;
    quantity_sold: number;
    order_frequency: number;
    turnover_ratio: number;
    last_order_days: number;
    current_stock: number;
    recommendation: string;
    risk_factors: string[];
    performance_indicators: {
        revenue_trend: string;
        consistency: string;
        profitability: string;
    };
}

interface AdvancedABCAnalysisProps {
    companyId?: string;
}

export function AdvancedABCAnalysis({ companyId }: AdvancedABCAnalysisProps) {
    const [products, setProducts] = useState<ABCProduct[]>([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [activeTab, setActiveTab] = useState('overview');

    const loadAbcAnalysis = async () => {
        setLoading(true);
        setError(null);
        try {
            const response = await fetch('/api/analytics/abc-analysis', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ companyId }),
            });

            if (!response.ok) {
                throw new Error('Failed to load ABC analysis');
            }

            const data = await response.json();
            setProducts(data.products || []);
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Failed to load analysis');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        loadAbcAnalysis();
    }, [companyId, loadAbcAnalysis]);

    const getCategoryColor = (category: string) => {
        switch (category) {
            case 'A': return 'bg-red-100 text-red-800 border-red-200';
            case 'B': return 'bg-yellow-100 text-yellow-800 border-yellow-200';
            case 'C': return 'bg-green-100 text-green-800 border-green-200';
            default: return 'bg-gray-100 text-gray-800 border-gray-200';
        }
    };

    const getPriorityIcon = (priority: string) => {
        switch (priority) {
            case 'Critical': return <AlertTriangle className="h-4 w-4 text-red-500" />;
            case 'Important': return <Star className="h-4 w-4 text-yellow-500" />;
            case 'Standard': return <Target className="h-4 w-4 text-green-500" />;
            default: return null;
        }
    };

    const categorySummary = products.reduce(
        (acc, product) => {
            acc[product.category].count++;
            acc[product.category].revenue += product.revenue;
            acc[product.category].margin += product.margin;
            return acc;
        },
        {
            A: { count: 0, revenue: 0, margin: 0 },
            B: { count: 0, revenue: 0, margin: 0 },
            C: { count: 0, revenue: 0, margin: 0 },
        }
    );

    const totalRevenue = products.reduce((sum, p) => sum + p.revenue, 0);

    if (loading) {
        return (
            <Card>
                <CardContent className="flex items-center justify-center py-12">
                    <Loader2 className="h-8 w-8 animate-spin mr-2" />
                    <span>Analyzing inventory data...</span>
                </CardContent>
            </Card>
        );
    }

    if (error) {
        return (
            <Card>
                <CardContent className="py-8">
                    <div className="text-center text-red-600">
                        <AlertTriangle className="h-8 w-8 mx-auto mb-2" />
                        <p>{error}</p>
                        <Button onClick={loadAbcAnalysis} className="mt-4">
                            Retry Analysis
                        </Button>
                    </div>
                </CardContent>
            </Card>
        );
    }

    if (products.length === 0) {
        return (
            <Card>
                <CardContent className="py-8 text-center">
                    <p className="text-gray-500">No data available for ABC analysis</p>
                    <p className="text-sm text-gray-400 mt-2">
                        Ensure you have order history and inventory data
                    </p>
                </CardContent>
            </Card>
        );
    }

    return (
        <div className="space-y-6">
            {/* Summary Cards */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                {Object.entries(categorySummary).map(([category, data]) => (
                    <Card key={category}>
                        <CardHeader className="pb-3">
                            <div className="flex items-center justify-between">
                                <CardTitle className="text-lg">Category {category}</CardTitle>
                                <Badge className={getCategoryColor(category)}>
                                    {data.count} products
                                </Badge>
                            </div>
                        </CardHeader>
                        <CardContent>
                            <div className="space-y-2">
                                <div className="flex items-center justify-between text-sm">
                                    <span>Revenue Share</span>
                                    <span className="font-medium">
                                        {((data.revenue / totalRevenue) * 100).toFixed(1)}%
                                    </span>
                                </div>
                                <Progress 
                                    value={(data.revenue / totalRevenue) * 100} 
                                    className="h-2"
                                />
                                <div className="flex items-center justify-between text-sm text-gray-600">
                                    <span>Total Revenue</span>
                                    <span>{formatCentsAsCurrency(data.revenue)}</span>
                                </div>
                                <div className="flex items-center justify-between text-sm text-gray-600">
                                    <span>Total Margin</span>
                                    <span>{formatCentsAsCurrency(data.margin)}</span>
                                </div>
                            </div>
                        </CardContent>
                    </Card>
                ))}
            </div>

            {/* Main Analysis */}
            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <DollarSign className="h-5 w-5" />
                        Advanced ABC Analysis
                    </CardTitle>
                    <div className="flex gap-2">
                        <Button
                            onClick={loadAbcAnalysis}
                            disabled={loading}
                            size="sm"
                            variant="outline"
                        >
                            {loading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                            Refresh Analysis
                        </Button>
                    </div>
                </CardHeader>
                <CardContent>
                    <Tabs value={activeTab} onValueChange={setActiveTab}>
                        <TabsList className="grid w-full grid-cols-4">
                            <TabsTrigger value="overview">Overview</TabsTrigger>
                            <TabsTrigger value="revenue">Revenue</TabsTrigger>
                            <TabsTrigger value="margin">Margin</TabsTrigger>
                            <TabsTrigger value="velocity">Velocity</TabsTrigger>
                        </TabsList>

                        <TabsContent value="overview" className="space-y-4">
                            <div className="space-y-3">
                                {products.slice(0, 20).map((product) => (
                                    <div
                                        key={product.sku}
                                        className="border rounded-lg p-4 space-y-3"
                                    >
                                        <div className="flex items-start justify-between">
                                            <div className="flex-1">
                                                <div className="flex items-center gap-2">
                                                    <h4 className="font-medium">{product.product_name}</h4>
                                                    <Badge className={getCategoryColor(product.category)}>
                                                        {product.category}
                                                    </Badge>
                                                    <div className="flex items-center gap-1">
                                                        {getPriorityIcon(product.priority)}
                                                        <span className="text-sm text-gray-600">
                                                            {product.priority}
                                                        </span>
                                                    </div>
                                                </div>
                                                <p className="text-sm text-gray-500">SKU: {product.sku}</p>
                                            </div>
                                            <div className="text-right">
                                                <div className="text-lg font-semibold">
                                                    Score: {product.composite_score}
                                                </div>
                                                <div className="text-sm text-gray-600">
                                                    Rank: #{product.revenue_rank}
                                                </div>
                                            </div>
                                        </div>

                                        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                                            <div>
                                                <span className="text-gray-600">Revenue</span>
                                                <div className="font-medium">
                                                    {formatCentsAsCurrency(product.revenue)}
                                                </div>
                                                <div className="text-xs text-gray-500">
                                                    {product.revenue_contribution.toFixed(1)}% of total
                                                </div>
                                            </div>
                                            <div>
                                                <span className="text-gray-600">Margin</span>
                                                <div className="font-medium">
                                                    {formatCentsAsCurrency(product.margin)}
                                                </div>
                                                <div className="text-xs text-gray-500">
                                                    {product.margin_percentage.toFixed(1)}%
                                                </div>
                                            </div>
                                            <div>
                                                <span className="text-gray-600">Velocity</span>
                                                <div className="font-medium">
                                                    {product.velocity} units/day
                                                </div>
                                                <div className="text-xs text-gray-500">
                                                    {product.quantity_sold} sold (90d)
                                                </div>
                                            </div>
                                            <div>
                                                <span className="text-gray-600">Stock</span>
                                                <div className="font-medium">
                                                    {product.current_stock} units
                                                </div>
                                                <div className="text-xs text-gray-500">
                                                    {product.turnover_ratio.toFixed(1)}x turnover
                                                </div>
                                            </div>
                                        </div>

                                        {product.risk_factors.length > 0 && (
                                            <div className="flex flex-wrap gap-1">
                                                {product.risk_factors.map((factor) => (
                                                    <Badge
                                                        key={factor}
                                                        variant="outline"
                                                        className="text-xs text-orange-700 border-orange-200"
                                                    >
                                                        {factor}
                                                    </Badge>
                                                ))}
                                            </div>
                                        )}

                                        <div className="bg-blue-50 p-3 rounded-md">
                                            <p className="text-sm text-blue-800">
                                                <strong>Recommendation:</strong> {product.recommendation}
                                            </p>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </TabsContent>

                        <TabsContent value="revenue">
                            <div className="space-y-3">
                                {products
                                    .sort((a, b) => b.revenue - a.revenue)
                                    .slice(0, 15)
                                    .map((product, index) => (
                                        <div
                                            key={product.sku}
                                            className="flex items-center justify-between p-3 border rounded-lg"
                                        >
                                            <div className="flex items-center gap-3">
                                                <span className="font-mono text-sm text-gray-500">
                                                    #{index + 1}
                                                </span>
                                                <div>
                                                    <h4 className="font-medium">{product.product_name}</h4>
                                                    <p className="text-sm text-gray-500">{product.sku}</p>
                                                </div>
                                                <Badge className={getCategoryColor(product.category)}>
                                                    {product.category}
                                                </Badge>
                                            </div>
                                            <div className="text-right">
                                                <div className="font-semibold">
                                                    {formatCentsAsCurrency(product.revenue)}
                                                </div>
                                                <div className="text-sm text-gray-500">
                                                    {product.revenue_contribution.toFixed(2)}% of total
                                                </div>
                                            </div>
                                        </div>
                                    ))}
                            </div>
                        </TabsContent>

                        <TabsContent value="margin">
                            <div className="space-y-3">
                                {products
                                    .sort((a, b) => b.margin_percentage - a.margin_percentage)
                                    .slice(0, 15)
                                    .map((product, index) => (
                                        <div
                                            key={product.sku}
                                            className="flex items-center justify-between p-3 border rounded-lg"
                                        >
                                            <div className="flex items-center gap-3">
                                                <span className="font-mono text-sm text-gray-500">
                                                    #{index + 1}
                                                </span>
                                                <div>
                                                    <h4 className="font-medium">{product.product_name}</h4>
                                                    <p className="text-sm text-gray-500">{product.sku}</p>
                                                </div>
                                                <Badge className={getCategoryColor(product.category)}>
                                                    {product.category}
                                                </Badge>
                                            </div>
                                            <div className="text-right">
                                                <div className="font-semibold">
                                                    {product.margin_percentage.toFixed(1)}%
                                                </div>
                                                <div className="text-sm text-gray-500">
                                                    {formatCentsAsCurrency(product.margin)} margin
                                                </div>
                                            </div>
                                        </div>
                                    ))}
                            </div>
                        </TabsContent>

                        <TabsContent value="velocity">
                            <div className="space-y-3">
                                {products
                                    .sort((a, b) => b.velocity - a.velocity)
                                    .slice(0, 15)
                                    .map((product, index) => (
                                        <div
                                            key={product.sku}
                                            className="flex items-center justify-between p-3 border rounded-lg"
                                        >
                                            <div className="flex items-center gap-3">
                                                <span className="font-mono text-sm text-gray-500">
                                                    #{index + 1}
                                                </span>
                                                <div>
                                                    <h4 className="font-medium">{product.product_name}</h4>
                                                    <p className="text-sm text-gray-500">{product.sku}</p>
                                                </div>
                                                <Badge className={getCategoryColor(product.category)}>
                                                    {product.category}
                                                </Badge>
                                            </div>
                                            <div className="text-right">
                                                <div className="font-semibold">
                                                    {product.velocity.toFixed(2)} units/day
                                                </div>
                                                <div className="text-sm text-gray-500">
                                                    {product.quantity_sold} sold (90d)
                                                </div>
                                            </div>
                                        </div>
                                    ))}
                            </div>
                        </TabsContent>
                    </Tabs>
                </CardContent>
            </Card>
        </div>
    );
}
