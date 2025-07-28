

'use client';

import { useState, useTransition } from 'react';
import type { DeadStockItem } from '@/types';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { TrendingDown, Package, Warehouse, Wand2, Loader2, Lightbulb } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import { formatCentsAsCurrency } from '@/lib/utils';
import { motion, AnimatePresence } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { generateMarkdownPlan } from '@/app/(app)/analytics/dead-stock/actions';

interface MarkdownPlan {
    suggestions: any[];
    analysis: string;
}

interface DeadStockClientPageProps {
  initialData: {
    deadStockItems: DeadStockItem[];
    totalValue: number;
    totalUnits: number;
    deadStockDays: number;
  };
}

const StatCard = ({ title, value, icon: Icon, description }: { title: string; value: string; icon: React.ElementType, description: string }) => (
    <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">{title}</CardTitle>
            <Icon className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
            <div className="text-2xl font-bold">{value}</div>
            <p className="text-xs text-muted-foreground">{description}</p>
        </CardContent>
    </Card>
);

function MarkdownPlanResults({ plan, onClear }: { plan: MarkdownPlan, onClear: () => void }) {
    return (
        <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            className="space-y-6"
        >
            <Card>
                <CardHeader>
                    <div className="flex justify-between items-start">
                        <div>
                            <CardTitle>AI-Generated Markdown Plan</CardTitle>
                            <CardDescription>A suggested strategy to liquidate dead stock and recover capital.</CardDescription>
                        </div>
                        <Button variant="ghost" size="sm" onClick={onClear}>Clear</Button>
                    </div>
                </CardHeader>
                <CardContent>
                     <Alert className="mb-6 bg-primary/5 border-primary/20">
                        <Lightbulb className="h-4 w-4" />
                        <AlertTitle>Analyst's Summary</AlertTitle>
                        <AlertDescription>{plan.analysis}</AlertDescription>
                    </Alert>
                    
                    <div className="space-y-4 max-h-[50vh] overflow-auto">
                        {plan.suggestions.map((item: any) => (
                            <div key={item.sku} className="border rounded-lg p-4">
                                <h4 className="font-semibold">{item.productName} ({item.sku})</h4>
                                <p className="text-sm text-muted-foreground">Current Stock: {item.currentStock} units ({formatCentsAsCurrency(item.totalValue)})</p>
                                <Table className="mt-2">
                                    <TableHeader>
                                        <TableRow>
                                            <TableHead>Phase</TableHead>
                                            <TableHead>Discount</TableHead>
                                            <TableHead>Duration</TableHead>
                                            <TableHead>Expected Sell-Through</TableHead>
                                        </TableRow>
                                    </TableHeader>
                                    <TableBody>
                                        {item.markdownStrategy.map((phase: any) => (
                                            <TableRow key={phase.phase}>
                                                <TableCell>{phase.phase}</TableCell>
                                                <TableCell>{phase.discountPercentage}%</TableCell>
                                                <TableCell>{phase.durationDays} days</TableCell>
                                                <TableCell>{phase.expectedSellThrough}%</TableCell>
                                            </TableRow>
                                        ))}
                                    </TableBody>
                                </Table>
                            </div>
                        ))}
                    </div>
                </CardContent>
            </Card>
        </motion.div>
    )
}

export function DeadStockClientPage({ initialData }: DeadStockClientPageProps) {
  const { deadStockItems, totalValue, totalUnits, deadStockDays } = initialData;
  const [markdownPlan, setMarkdownPlan] = useState<MarkdownPlan | null>(null);
  const [isPending, startTransition] = useTransition();

  const handleGeneratePlan = () => {
    startTransition(async () => {
        const plan = await generateMarkdownPlan();
        setMarkdownPlan(plan);
    });
  };

  if (deadStockItems.length === 0) {
    return (
      <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
        <motion.div
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
          className="relative bg-primary/10 rounded-full p-6"
        >
          <TrendingDown className="h-16 w-16 text-primary" />
        </motion.div>
        <h3 className="mt-6 text-xl font-semibold">No Dead Stock Found!</h3>
        <p className="mt-2 text-muted-foreground">
          All your inventory has sold within the last {deadStockDays} days. Great job!
        </p>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
       <AnimatePresence>
       {markdownPlan ? (
            <MarkdownPlanResults plan={markdownPlan} onClear={() => setMarkdownPlan(null)} />
       ) : (
            <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="space-y-6"
            >
                <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                    <StatCard title="Dead Stock Value" value={formatCentsAsCurrency(totalValue)} icon={Warehouse} description="Total capital tied up in unsold items." />
                    <StatCard title="Dead Stock Units" value={totalUnits.toLocaleString()} icon={Package} description="Total units considered dead stock." />
                    <StatCard title="Analysis Period" value={`${deadStockDays} Days`} icon={TrendingDown} description="Items unsold for this duration." />
                </div>

                <Card>
                    <CardHeader>
                        <div className="flex flex-col md:flex-row justify-between items-start gap-4">
                            <div>
                                <CardTitle>Dead Stock Report</CardTitle>
                                <CardDescription>
                                    Products that have not sold in the last {deadStockDays} days and may require action.
                                </CardDescription>
                            </div>
                            <Button onClick={handleGeneratePlan} disabled={isPending}>
                                {isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Wand2 className="mr-2 h-4 w-4" />}
                                Generate Markdown Plan
                            </Button>
                        </div>
                    </CardHeader>
                    <CardContent className="p-0">
                    <div className="overflow-x-auto">
                        <Table>
                        <TableHeader>
                            <TableRow>
                            <TableHead>Product</TableHead>
                            <TableHead className="text-right">Quantity</TableHead>
                            <TableHead className="text-right">Total Value</TableHead>
                            <TableHead>Last Sale Date</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {deadStockItems.map((item) => (
                            <TableRow key={item.sku}>
                                <TableCell>
                                <div className="font-medium">{item.product_name}</div>
                                <div className="text-xs text-muted-foreground">{item.sku}</div>
                                </TableCell>
                                <TableCell className="text-right font-tabular">{item.quantity}</TableCell>
                                <TableCell className="text-right font-medium font-tabular">{formatCentsAsCurrency(item.total_value)}</TableCell>
                                <TableCell>
                                {item.last_sale_date
                                    ? formatDistanceToNow(new Date(item.last_sale_date), { addSuffix: true })
                                    : 'Never'}
                                </TableCell>
                            </TableRow>
                            ))}
                        </TableBody>
                        </Table>
                    </div>
                    </CardContent>
                </Card>
            </motion.div>
       )}
        </AnimatePresence>
    </div>
  );
}
