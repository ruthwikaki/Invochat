
'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { formatCentsAsCurrency } from '@/lib/utils';
import { motion } from 'framer-motion';
import { BarChart3 } from 'lucide-react';

// Define types for the report data
type AbcAnalysisItem = {
    sku: string;
    product_name: string;
    revenue: number;
    cumulative_revenue_percentage: number;
    abc_category: 'A' | 'B' | 'C';
};

interface AdvancedReportsClientPageProps {
  abcAnalysisData: AbcAnalysisItem[];
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

export function AdvancedReportsClientPage({ abcAnalysisData }: AdvancedReportsClientPageProps) {
  return (
    <Tabs defaultValue="abc-analysis" className="space-y-4">
        <TabsList>
            <TabsTrigger value="abc-analysis">ABC Analysis</TabsTrigger>
        </TabsList>
        <TabsContent value="abc-analysis">
            <AbcAnalysisTab data={abcAnalysisData} />
        </TabsContent>
    </Tabs>
  );
}
