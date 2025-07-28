
'use client';

import { useState, useTransition } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Loader2, Wand2, Lightbulb, Package, ShoppingCart, TrendingUp, Search } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { formatCentsAsCurrency } from '@/lib/utils';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Textarea } from '@/components/ui/textarea';

interface MarkdownPlan {
    suggestions: any[];
    analysis: string;
}

interface BundleSuggestions {
    suggestions: any[];
    analysis: string;
}

interface PriceOptimization {
    suggestions: any[];
    analysis: string;
}

interface HiddenMoney {
    opportunities: any[];
    analysis: string;
}

interface PromotionalImpact {
    estimated_impact: {
        total_revenue_increase: number;
        total_profit_increase: number;
        estimated_units_sold: number;
        breakeven_unit_increase: number;
    },
    product_breakdown: any[];
    summary: string;
}


interface AiInsightsClientPageProps {
  generateMarkdownPlanAction: () => Promise<MarkdownPlan>;
  generateBundleSuggestionsAction: (count: number) => Promise<BundleSuggestions>;
  generatePriceOptimizationAction: () => Promise<PriceOptimization>;
  generateHiddenMoneyAction: () => Promise<HiddenMoney>;
  generatePromotionalImpactAction: (skus: string[], discount: number, duration: number) => Promise<PromotionalImpact>;
}

function PromotionalImpactResults({ data }: { data: PromotionalImpact }) {
    if (!data) return <p className="text-muted-foreground">The AI did not generate a promotional impact analysis.</p>;

    const { estimated_impact, product_breakdown, summary } = data;

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
                <AlertDescription>{summary}</AlertDescription>
            </Alert>

            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 text-center">
                <Card>
                    <CardHeader><CardTitle>{formatCentsAsCurrency(estimated_impact.total_revenue_increase)}</CardTitle></CardHeader>
                    <CardContent><p className="text-sm text-muted-foreground">Est. Revenue Lift</p></CardContent>
                </Card>
                 <Card>
                    <CardHeader><CardTitle>{formatCentsAsCurrency(estimated_impact.total_profit_increase)}</CardTitle></CardHeader>
                    <CardContent><p className="text-sm text-muted-foreground">Est. Profit Lift</p></CardContent>
                </Card>
                 <Card>
                    <CardHeader><CardTitle>{estimated_impact.estimated_units_sold}</CardTitle></CardHeader>
                    <CardContent><p className="text-sm text-muted-foreground">Est. Units Sold</p></CardContent>
                </Card>
                 <Card>
                    <CardHeader><CardTitle>{estimated_impact.breakeven_unit_increase}%</CardTitle></CardHeader>
                    <CardContent><p className="text-sm text-muted-foreground">Breakeven Sales Lift</p></CardContent>
                </Card>
            </div>
        </motion.div>
    );
}

function HiddenMoneyResults({ data }: { data: HiddenMoney }) {
    if (!data || !data.opportunities || data.opportunities.length === 0) return <p className="text-muted-foreground">The AI did not find any specific hidden money opportunities at this time.</p>;
    
    const getOpportunityBadge = (type: string) => {
        switch (type) {
            case 'High-Margin Slow-Mover': return <Badge variant="secondary" className="bg-amber-500/10 text-amber-600 dark:text-amber-400 border-amber-500/20">{type}</Badge>;
            case 'Price Increase Candidate': return <Badge variant="secondary" className="bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border-emerald-500/20">{type}</Badge>;
            default: return <Badge>{type}</Badge>;
        }
    }

    return (
         <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            className="space-y-6"
        >
            <Alert className="mb-6 bg-primary/5 border-primary/20">
                <Lightbulb className="h-4 w-4" />
                <AlertTitle>AI Business Consultant's Summary</AlertTitle>
                <AlertDescription>{data.analysis}</AlertDescription>
            </Alert>
            
             <div className="max-h-[60vh] overflow-auto">
                <Table>
                    <TableHeader>
                        <TableRow>
                            <TableHead>Product</TableHead>
                            <TableHead>Opportunity Type</TableHead>
                            <TableHead>Reasoning</TableHead>
                            <TableHead>Suggested Action</TableHead>
                            <TableHead className="text-right">Potential Value</TableHead>
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {data.opportunities.map((item: any, index: number) => (
                            <TableRow key={index}>
                                <TableCell>
                                    <div className="font-medium">{item.productName}</div>
                                    <div className="text-xs text-muted-foreground">{item.sku}</div>
                                </TableCell>
                                <TableCell>{getOpportunityBadge(item.type)}</TableCell>
                                <TableCell className="text-xs">{item.reasoning}</TableCell>
                                <TableCell className="text-xs font-medium">{item.suggestedAction}</TableCell>
                                <TableCell className="text-right font-tabular font-semibold text-success">{formatCentsAsCurrency(item.potentialValue)}</TableCell>
                            </TableRow>
                        ))}
                    </TableBody>
                </Table>
            </div>
        </motion.div>
    )
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

function PriceOptimizationResults({ optimization }: { optimization: PriceOptimization }) {
    if (!optimization || !optimization.suggestions || optimization.suggestions.length === 0) return <p className="text-muted-foreground">The AI could not generate price suggestions. Ensure products have cost and price data.</p>;
    return (
         <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            className="space-y-6"
        >
            <Alert className="mb-6 bg-primary/5 border-primary/20">
                <Lightbulb className="h-4 w-4" />
                <AlertTitle>AI Pricing Analyst's Summary</AlertTitle>
                <AlertDescription>{optimization.analysis}</AlertDescription>
            </Alert>
            
             <div className="max-h-[60vh] overflow-auto">
                <Table>
                    <TableHeader>
                        <TableRow>
                            <TableHead>Product</TableHead>
                            <TableHead className="text-right">Current Price</TableHead>
                            <TableHead className="text-right">Suggested Price</TableHead>
                            <TableHead>Reasoning</TableHead>
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {optimization.suggestions.map((item: any) => (
                            <TableRow key={item.sku}>
                                <TableCell>
                                    <div className="font-medium">{item.productName}</div>
                                    <div className="text-xs text-muted-foreground">{item.sku}</div>
                                </TableCell>
                                <TableCell className="text-right font-tabular">{formatCentsAsCurrency(item.currentPrice)}</TableCell>
                                <TableCell className="text-right font-tabular font-bold text-primary">{formatCentsAsCurrency(item.suggestedPrice)}</TableCell>
                                <TableCell className="text-xs">{item.reasoning}</TableCell>
                            </TableRow>
                        ))}
                    </TableBody>
                </Table>
            </div>
        </motion.div>
    )
}

export function AiInsightsClientPage({ generateMarkdownPlanAction, generateBundleSuggestionsAction, generatePriceOptimizationAction, generateHiddenMoneyAction, generatePromotionalImpactAction }: AiInsightsClientPageProps) {
  const [markdownPlan, setMarkdownPlan] = useState<MarkdownPlan | null>(null);
  const [isMarkdownPending, startMarkdownTransition] = useTransition();

  const [bundleSuggestions, setBundleSuggestions] = useState<BundleSuggestions | null>(null);
  const [isBundlePending, startBundleTransition] = useTransition();
  const [bundleCount, setBundleCount] = useState(3);

  const [priceOptimization, setPriceOptimization] = useState<PriceOptimization | null>(null);
  const [isPricePending, startPriceTransition] = useTransition();

  const [hiddenMoney, setHiddenMoney] = useState<HiddenMoney | null>(null);
  const [isHiddenMoneyPending, startHiddenMoneyTransition] = useTransition();

  const [promotionalImpact, setPromotionalImpact] = useState<PromotionalImpact | null>(null);
  const [isPromoPending, startPromoTransition] = useTransition();
  const [promoSkus, setPromoSkus] = useState('');
  const [promoDiscount, setPromoDiscount] = useState(15);
  const [promoDuration, setPromoDuration] = useState(14);


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

  const handleGeneratePrices = () => {
    startPriceTransition(async () => {
        const prices = await generatePriceOptimizationAction();
        setPriceOptimization(prices);
    });
  };

  const handleGenerateHiddenMoney = () => {
    startHiddenMoneyTransition(async () => {
        const money = await generateHiddenMoneyAction();
        setHiddenMoney(money);
    });
  };
  
  const handleGeneratePromoImpact = () => {
    startPromoTransition(async () => {
        const skusArray = promoSkus.split(',').map(s => s.trim()).filter(s => s);
        const impact = await generatePromotionalImpactAction(skusArray, promoDiscount / 100, promoDuration);
        setPromotionalImpact(impact);
    });
  };

  return (
    <div className="space-y-8">
        <Card>
            <CardHeader>
                <div className="flex flex-col md:flex-row justify-between items-start gap-4">
                    <div>
                        <CardTitle className="flex items-center gap-2"><Search className="h-5 w-5 text-primary"/> Hidden Money Finder</CardTitle>
                        <CardDescription>
                           Let AI find non-obvious opportunities, like high-margin, slow-moving products.
                        </CardDescription>
                    </div>
                    <Button onClick={handleGenerateHiddenMoney} disabled={isHiddenMoneyPending}>
                        {isHiddenMoneyPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Wand2 className="mr-2 h-4 w-4" />}
                        Find Opportunities
                    </Button>
                </div>
            </CardHeader>
            <AnimatePresence>
            {hiddenMoney && (
                <CardContent>
                    <HiddenMoneyResults data={hiddenMoney} />
                </CardContent>
            )}
            </AnimatePresence>
        </Card>

        <Card>
            <CardHeader>
                 <CardTitle className="flex items-center gap-2"><TrendingUp className="h-5 w-5 text-primary"/> Promotional Impact Analysis</CardTitle>
                <CardDescription>
                    Let AI model the financial impact of a planned promotion or sale before you run it.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <div>
                        <Label htmlFor="promo-skus">Product SKUs (comma-separated)</Label>
                        <Textarea id="promo-skus" placeholder="SKU001, SKU002, SKU005" value={promoSkus} onChange={e => setPromoSkus(e.target.value)} />
                    </div>
                     <div>
                        <Label htmlFor="promo-discount">Discount (%)</Label>
                        <Input id="promo-discount" type="number" value={promoDiscount} onChange={e => setPromoDiscount(Number(e.target.value))} />
                    </div>
                     <div>
                        <Label htmlFor="promo-duration">Duration (days)</Label>
                        <Input id="promo-duration" type="number" value={promoDuration} onChange={e => setPromoDuration(Number(e.target.value))} />
                    </div>
                </div>
                 <Button onClick={handleGeneratePromoImpact} disabled={isPromoPending} className="mt-4">
                    {isPromoPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Wand2 className="mr-2 h-4 w-4" />}
                    Analyze Promotion
                </Button>
            </CardContent>
            <AnimatePresence>
            {promotionalImpact && (
                <CardContent>
                    <PromotionalImpactResults data={promotionalImpact} />
                </CardContent>
            )}
            </AnimatePresence>
        </Card>

        <Card>
            <CardHeader>
                <div className="flex flex-col md:flex-row justify-between items-start gap-4">
                    <div>
                        <CardTitle className="flex items-center gap-2"><TrendingUp className="h-5 w-5 text-primary"/> Price Optimizer</CardTitle>
                        <CardDescription>
                           Let AI analyze sales velocity and suggest price changes to maximize profit.
                        </CardDescription>
                    </div>
                    <Button onClick={handleGeneratePrices} disabled={isPricePending}>
                        {isPricePending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Wand2 className="mr-2 h-4 w-4" />}
                        Generate Price Suggestions
                    </Button>
                </div>
            </CardHeader>
            <AnimatePresence>
            {priceOptimization && (
                <CardContent>
                    <PriceOptimizationResults optimization={priceOptimization} />
                </CardContent>
            )}
            </AnimatePresence>
        </Card>
        
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
