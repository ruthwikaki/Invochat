
'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { formatCentsAsCurrency } from '@/lib/utils';
import { motion } from 'framer-motion';
import { BarChart3, LineChart, PackageSearch } from 'lucide-react';

// Define types for the report data
type AbcAnalysisItem = {
    sku: string;
    product_name: string;
    revenue: number;
    cumulative_revenue_percentage: number;
    abc_category: 'A' | 'B' | 'C';
};

type SalesVelocityItem = {
    sku: string;
    product_name: string;
    units_sold: number;
    sales_velocity: number;
};

type GrossMarginItem = {
    sku: string;
    product_name: string;
    total_revenue: number;
    total_cogs: number;
    gross_margin_percentage: number;
    gross_profit: number;
}

interface AdvancedReportsClientPageProps {
  abcAnalysisData: AbcAnalysisItem[];
  salesVelocityData: {
    fast_sellers: SalesVelocityItem[];
    slow_sellers: SalesVelocityItem[];
  };
  grossMarginData: GrossMarginItem[];
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

function AbcAnalysisTab({ data }: { data: AbcAnalysisItem[] }) {
    if (!data || data.length === 0) return <ReportEmptyState title="No ABC Analysis Data" description="This report requires sales data. Once you have sales, we can categorize your products." icon={BarChart3} />;
    return (
        <Card>
            <CardHeader>
                <CardTitle>ABC Analysis Report</CardTitle>
                <CardDescription>
                    Products are categorized into A, B, and C tiers based on their revenue contribution. 'A' items are your most valuable products.
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

function SalesVelocityTab({ data }: { data: { fast_sellers: SalesVelocityItem[], slow_sellers: SalesVelocityItem[] } }) {
    if (!data || (data.fast_sellers.length === 0 && data.slow_sellers.length === 0)) return <ReportEmptyState title="No Sales Velocity Data" description="This report is generated from your sales history. Sync your sales to see which products move fastest and slowest." icon={LineChart} />;

    const VelocityTable = ({ title, items }: { title: string, items: SalesVelocityItem[] }) => (
        <Card className="flex-1">
            <CardHeader>
                <CardTitle>{title}</CardTitle>
            </CardHeader>
            <CardContent>
                 <div className="max-h-[45vh] overflow-auto">
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Product</TableHead>
                                <TableHead className="text-right">Units Sold/Day</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {items.length > 0 ? items.map(item => (
                                <TableRow key={item.sku}>
                                    <TableCell>
                                        <div className="font-medium">{item.product_name}</div>
                                        <div className="text-xs text-muted-foreground">{item.sku}</div>
                                    </TableCell>
                                    <TableCell className="text-right font-tabular">{item.sales_velocity.toFixed(2)}</TableCell>
                                </TableRow>
                            )) : (
                                <TableRow>
                                    <TableCell colSpan={2} className="text-center text-muted-foreground h-24">No data for this category.</TableCell>
                                </TableRow>
                            )}
                        </TableBody>
                    </Table>
                </div>
            </CardContent>
        </Card>
    );
    
    return (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <VelocityTable title="Fastest-Selling Products" items={data.fast_sellers} />
            <VelocityTable title="Slowest-Selling Products" items={data.slow_sellers} />
        </div>
    );
}

function GrossMarginTab({ data }: { data: GrossMarginItem[] }) {
    if (!data || data.length === 0) return <ReportEmptyState title="No Gross Margin Data" description="Profitability analysis requires both sales prices and product costs. Ensure your products have cost data imported." icon={PackageSearch} />;
    return (
        <Card>
            <CardHeader>
                <CardTitle>Gross Margin Report</CardTitle>
                <CardDescription>
                    Analyze the profitability of each product based on its revenue and cost of goods sold (COGS).
                </CardDescription>
            </CardHeader>
            <CardContent>
                <div className="max-h-[60vh] overflow-auto">
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Product</TableHead>
                                <TableHead className="text-right">Gross Profit</TableHead>
                                <TableHead className="text-right">Gross Margin</TableHead>
                                <TableHead className="text-right">Total Revenue</TableHead>
                                <TableHead className="text-right">Total COGS</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {data.map((item, index) => (
                                <motion.tr key={item.sku} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: index * 0.05 }}>
                                    <TableCell>
                                        <div className="font-medium">{item.product_name}</div>
                                        <div className="text-xs text-muted-foreground">{item.sku}</div>
                                    </TableCell>
                                    <TableCell className="text-right font-tabular font-semibold">{formatCentsAsCurrency(item.gross_profit)}</TableCell>
                                    <TableCell className="text-right font-tabular">{item.gross_margin_percentage.toFixed(1)}%</TableCell>
                                    <TableCell className="text-right font-tabular">{formatCentsAsCurrency(item.total_revenue)}</TableCell>
                                    <TableCell className="text-right font-tabular">{formatCentsAsCurrency(item.total_cogs)}</TableCell>
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
