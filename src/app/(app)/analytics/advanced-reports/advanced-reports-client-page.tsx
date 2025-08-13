
'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { formatCentsAsCurrency } from '@/lib/utils';
import { motion } from 'framer-motion';
import { BarChart3, TrendingUp, TrendingDown, DollarSign, LineChart } from 'lucide-react';

// Define types for the report data
export type AbcAnalysisItem = {
    sku: string;
    product_name: string;
    revenue: number;
    cumulative_revenue_percentage: number;
    abc_category: 'A' | 'B' | 'C';
};

export type SalesVelocityItem = {
    sku: string;
    product_name: string;
    units_sold: number;
    total_revenue: number;
};

export type GrossMarginItem = {
    sku: string;
    product_name: string;
    total_revenue: number;
    total_cogs: number;
    gross_margin: number;
    margin_percentage: number;
};

interface AdvancedReportsClientPageProps {
  abcAnalysisData: AbcAnalysisItem[];
  salesVelocityData: {
      fast_sellers: SalesVelocityItem[];
      slow_sellers: SalesVelocityItem[];
  };
  grossMarginData: {
      products: GrossMarginItem[];
      summary: {
          total_revenue: number;
          total_cogs: number;
          total_gross_margin: number;
          average_gross_margin: number;
      };
  };
}

const ReportEmptyState = ({ title, description, icon: Icon }: { title: string, description: string, icon: React.ElementType }) => (
    <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed h-full min-h-[400px]">
         <motion.div
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
            className="relative bg-primary/10 rounded-full p-6"
        >
            <Icon className="h-16 w-16 text-primary" />
        </motion.div>
        <h3 className="mt-6 text-xl font-semibold">{title}</h3>
        <p className="mt-2 text-muted-foreground">{description}</p>
    </Card>
);

const getCategoryBadgeClass = (category: 'A' | 'B' | 'C') => {
    switch (category) {
        case 'A': return 'bg-success/10 text-success-foreground border-success/20';
        case 'B': return 'bg-warning/10 text-amber-600 dark:text-amber-400 border-warning/20';
        case 'C': return 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/20';
        default: return 'bg-muted';
    }
};

function GrossMarginTab({ data }: { data: AdvancedReportsClientPageProps['grossMarginData']}) {
    if (!data || !data.products || data.products.length === 0) return <ReportEmptyState title="No Gross Margin Data" description="This report requires sales and product cost data. Import both to see your profit margins." icon={DollarSign} />;
    
    return (
         <Card>
            <CardHeader>
                <CardTitle>Gross Margin Report</CardTitle>
                <CardDescription>
                    Analyze the profitability of each product sold.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                    <div className="p-4 border rounded-lg">
                        <div className="text-sm text-muted-foreground">Total Revenue</div>
                        <div className="text-xl font-bold">{formatCentsAsCurrency(data.summary.total_revenue)}</div>
                    </div>
                     <div className="p-4 border rounded-lg">
                        <div className="text-sm text-muted-foreground">Total COGS</div>
                        <div className="text-xl font-bold">{formatCentsAsCurrency(data.summary.total_cogs)}</div>
                    </div>
                     <div className="p-4 border rounded-lg">
                        <div className="text-sm text-muted-foreground">Gross Margin</div>
                        <div className="text-xl font-bold text-success">{formatCentsAsCurrency(data.summary.total_gross_margin)}</div>
                    </div>
                     <div className="p-4 border rounded-lg">
                        <div className="text-sm text-muted-foreground">Average Margin</div>
                        <div className="text-xl font-bold text-success">{(data.summary.average_gross_margin * 100).toFixed(1)}%</div>
                    </div>
                </div>
                 <div className="max-h-[60vh] overflow-auto">
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Product</TableHead>
                                <TableHead className="text-right">Total Revenue</TableHead>
                                <TableHead className="text-right">Gross Margin</TableHead>
                                <TableHead className="text-right">Margin %</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {data.products.map((item, index) => (
                                <motion.tr key={item.sku} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: index * 0.05 }}>
                                    <TableCell>
                                        <div className="font-medium">{item.product_name}</div>
                                        <div className="text-xs text-muted-foreground">{item.sku}</div>
                                    </TableCell>
                                    <TableCell className="text-right font-tabular">{formatCentsAsCurrency(item.total_revenue)}</TableCell>
                                    <TableCell className="text-right font-tabular text-success">{formatCentsAsCurrency(item.gross_margin)}</TableCell>
                                    <TableCell className="text-right font-tabular font-semibold">{(item.margin_percentage * 100).toFixed(1)}%</TableCell>
                                </motion.tr>
                            ))}
                        </TableBody>
                    </Table>
                </div>
            </CardContent>
        </Card>
    );
}

function SalesVelocityTab({ data }: { data: AdvancedReportsClientPageProps['salesVelocityData']}) {
     if (!data || (data.fast_sellers.length === 0 && data.slow_sellers.length === 0)) return <ReportEmptyState title="Not Enough Data for Sales Velocity" description="Sales velocity requires a history of sales data to identify trends. Keep selling!" icon={LineChart} />;
    
    return (
        <div className="grid md:grid-cols-2 gap-6">
            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2"><TrendingUp className="text-success" /> Fast-Moving Products</CardTitle>
                    <CardDescription>Your best sellers by units sold in the last 90 days.</CardDescription>
                </CardHeader>
                <CardContent>
                    <Table>
                        <TableHeader>
                             <TableRow>
                                <TableHead>Product</TableHead>
                                <TableHead className="text-right">Units Sold</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {data.fast_sellers.map((item) => (
                                <TableRow key={item.sku}>
                                    <TableCell>
                                        <div className="font-medium">{item.product_name}</div>
                                        <div className="text-xs text-muted-foreground">{item.sku}</div>
                                    </TableCell>
                                    <TableCell className="text-right font-bold">{item.units_sold}</TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                </CardContent>
            </Card>
            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2"><TrendingDown className="text-destructive" /> Slow-Moving Products</CardTitle>
                    <CardDescription>Your worst sellers by units sold in the last 90 days.</CardDescription>
                </CardHeader>
                <CardContent>
                     <Table>
                        <TableHeader>
                             <TableRow>
                                <TableHead>Product</TableHead>
                                <TableHead className="text-right">Units Sold</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {data.slow_sellers.map((item) => (
                                <TableRow key={item.sku}>
                                    <TableCell>
                                        <div className="font-medium">{item.product_name}</div>
                                        <div className="text-xs text-muted-foreground">{item.sku}</div>
                                    </TableCell>
                                    <TableCell className="text-right font-bold">{item.units_sold}</TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                </CardContent>
            </Card>
        </div>
    );
}

function AbcAnalysisTab({ data }: { data: AbcAnalysisItem[] }) {
    if (!data || data.length === 0) return <ReportEmptyState title="No ABC Analysis Data" description="This report requires sales data. Once you have sales, we can categorize your products." icon={BarChart3} />;
    return (
        <Card>
            <CardHeader>
                <CardTitle>ABC Analysis Report</CardTitle>
                <CardDescription>
                    Products are categorized into A, B, and C tiers based on their revenue contribution. &apos;A&apos; items are your most valuable products.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <div className="max-h-[60vh] overflow-auto">
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Product</TableHead>
                                <TableHead>Category</TableHead>
                                <TableHead className="text-right">Revenue</TableHead>
                                <TableHead className="text-right">Cumulative %</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {data.map((item, index) => (
                                <motion.tr key={item.sku} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: index * 0.05 }}>
                                    <TableCell>
                                        <div className="font-medium">{item.product_name}</div>
                                        <div className="text-xs text-muted-foreground">{item.sku}</div>
                                    </TableCell>
                                    <TableCell>
                                        <Badge className={getCategoryBadgeClass(item.abc_category)}>{item.abc_category}</Badge>
                                    </TableCell>
                                    <TableCell className="text-right font-tabular">{formatCentsAsCurrency(item.revenue)}</TableCell>
                                    <TableCell className="text-right font-tabular">{(item.cumulative_revenue_percentage * 100).toFixed(1)}%</TableCell>
                                </motion.tr>
                            ))}
                        </TableBody>
                    </Table>
                </div>
            </CardContent>
        </Card>
    );
}

export function AdvancedReportsClientPage({ abcAnalysisData, salesVelocityData, grossMarginData }: AdvancedReportsClientPageProps) {
  return (
    <Tabs defaultValue="abc-analysis" className="space-y-4">
        <TabsList>
            <TabsTrigger value="abc-analysis">ABC Analysis</TabsTrigger>
            <TabsTrigger value="sales-velocity">Sales Velocity</TabsTrigger>
            <TabsTrigger value="gross-margin">Gross Margin</TabsTrigger>
        </TabsList>
        <TabsContent value="abc-analysis">
            <AbcAnalysisTab data={abcAnalysisData} />
        </TabsContent>
        <TabsContent value="sales-velocity">
            <SalesVelocityTab data={salesVelocityData} />
        </TabsContent>
        <TabsContent value="gross-margin">
            <GrossMarginTab data={grossMarginData} />
        </TabsContent>
    </Tabs>
  );
}
    