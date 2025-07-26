
'use client';

import { useState, useTransition } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Loader2, Wand2, Lightbulb, Package, ShoppingCart } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { formatCentsAsCurrency } from '@/lib/utils';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

interface MarkdownPlan {
    suggestions: any[];
    analysis: string;
}

interface BundleSuggestions {
    suggestions: any[];
    analysis: string;
}

interface AiInsightsClientPageProps {
  generateMarkdownPlanAction: () => Promise<MarkdownPlan>;
  generateBundleSuggestionsAction: (count: number) => Promise<BundleSuggestions>;
}

function MarkdownPlanResults({ plan }: { plan: MarkdownPlan }) {
    if (!plan || !plan.suggestions || plan.suggestions.length === 0) return <p className="text-muted-foreground">No markdown suggestions generated. This may mean you have no dead stock.</p>;

    return (
        <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            className="space-y-6"
        >
            <Alert className="mb-6 bg-primary/5 border-primary/20">
                <Lightbulb className="h-4 w-4" />
                <AlertTitle>AI Analyst's Summary</AlertTitle>
                <AlertDescription>{plan.analysis}</AlertDescription>
            </Alert>
            
            <div className="space-y-4 max-h-[60vh] overflow-auto">
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
        </motion.div>
    );
}

function BundleResults({ bundles }: { bundles: BundleSuggestions }) {
    if (!bundles || !bundles.suggestions || bundles.suggestions.length === 0) return <p className="text-muted-foreground">The AI could not generate bundle suggestions with your current product catalog.</p>;
    return (
         <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            className="space-y-6"
        >
            <Alert className="mb-6 bg-primary/5 border-primary/20">
                <Lightbulb className="h-4 w-4" />
                <AlertTitle>AI Merchandiser's Summary</AlertTitle>
                <AlertDescription>{bundles.analysis}</AlertDescription>
            </Alert>
            
            <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
                {bundles.suggestions.map((item: any, index: number) => (
                    <Card key={index}>
                        <CardHeader>
                            <CardTitle className="text-lg">{item.bundleName}</CardTitle>
                             <CardDescription>{item.potentialBenefit}</CardDescription>
                        </CardHeader>
                        <CardContent>
                           <div className="space-y-2">
                                <h4 className="font-semibold text-sm">Products:</h4>
                                <ul className="list-disc list-inside text-muted-foreground text-sm">
                                    {item.productSkus.map((sku: string) => <li key={sku}>{sku}</li>)}
                                </ul>
                                <p className="text-xs pt-2 italic">"{item.reasoning}"</p>
                           </div>
                        </CardContent>
                    </Card>
                ))}
            </div>
        </motion.div>
    )
}

export function AiInsightsClientPage({ generateMarkdownPlanAction, generateBundleSuggestionsAction }: AiInsightsClientPageProps) {
  const [markdownPlan, setMarkdownPlan] = useState<MarkdownPlan | null>(null);
  const [isMarkdownPending, startMarkdownTransition] = useTransition();

  const [bundleSuggestions, setBundleSuggestions] = useState<BundleSuggestions | null>(null);
  const [isBundlePending, startBundleTransition] = useTransition();
  const [bundleCount, setBundleCount] = useState(3);


  const handleGenerateMarkdownPlan = () => {
    startMarkdownTransition(async () => {
        const plan = await generateMarkdownPlanAction();
        setMarkdownPlan(plan);
    });
  };

  const handleGenerateBundles = () => {
    startBundleTransition(async () => {
        const bundles = await generateBundleSuggestionsAction(bundleCount);
        setBundleSuggestions(bundles);
    });
  };

  return (
    <div className="space-y-8">
        <Card>
            <CardHeader>
                <div className="flex flex-col md:flex-row justify-between items-start gap-4">
                    <div>
                        <CardTitle className="flex items-center gap-2"><Package className="h-5 w-5 text-primary"/> Product Bundle Suggester</CardTitle>
                        <CardDescription>
                            Let AI act as your merchandiser to find profitable product bundles.
                        </CardDescription>
                    </div>
                     <div className="flex items-center gap-2">
                        <Label htmlFor="bundle-count" className="whitespace-nowrap">Suggestions:</Label>
                        <Input id="bundle-count" type="number" value={bundleCount} onChange={(e) => setBundleCount(Number(e.target.value))} className="w-20" min="1" max="9" />
                        <Button onClick={handleGenerateBundles} disabled={isBundlePending}>
                            {isBundlePending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Wand2 className="mr-2 h-4 w-4" />}
                            Generate Bundles
                        </Button>
                    </div>
                </div>
            </CardHeader>
            <AnimatePresence>
            {bundleSuggestions && (
                <CardContent>
                     <BundleResults bundles={bundleSuggestions} />
                </CardContent>
            )}
            </AnimatePresence>
        </Card>

        <Card>
            <CardHeader>
                <div className="flex flex-col md:flex-row justify-between items-start gap-4">
                    <div>
                        <CardTitle className="flex items-center gap-2"><ShoppingCart className="h-5 w-5 text-primary"/> Markdown Optimizer</CardTitle>
                        <CardDescription>
                           Generate a phased markdown plan to liquidate dead stock and recover capital.
                        </CardDescription>
                    </div>
                    <Button onClick={handleGenerateMarkdownPlan} disabled={isMarkdownPending}>
                        {isMarkdownPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Wand2 className="mr-2 h-4 w-4" />}
                        Generate Markdown Plan
                    </Button>
                </div>
            </CardHeader>
            <AnimatePresence>
            {markdownPlan && (
                <CardContent>
                    <MarkdownPlanResults plan={markdownPlan} />
                </CardContent>
            )}
            </AnimatePresence>
        </Card>
    </div>
  );
}
