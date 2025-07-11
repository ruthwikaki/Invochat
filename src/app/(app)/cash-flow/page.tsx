import { AppPage, AppPageHeader } from '@/components/ui/page';
import { getCashFlowInsights } from '@/app/data-actions';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { DollarSign, AlertCircle, Clock, TrendingDown, Package, Bot } from 'lucide-react';
import Link from 'next/link';
import { Button } from '@/components/ui/button';

function formatCurrency(value: number) {
  if (value === 0) return '$0';
  if (Math.abs(value) >= 1_000_000) return `$${(value / 1_000_000).toFixed(1)}M`;
  if (Math.abs(value) >= 1_000) return `$${(value / 1_000).toFixed(1)}k`;
  return `$${value.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`;
}

function MetricCard({ title, value, icon: Icon, description, colorClass, actionLink, actionText }: { title: string, value: number, icon: React.ElementType, description: string, colorClass: string, actionLink: string, actionText: string }) {
  return (
    <Card className={`overflow-hidden relative border-2 ${colorClass}`}>
       <div className={`absolute -top-4 -right-4 h-24 w-24 rounded-full opacity-10 ${colorClass.replace('border-', 'bg-')}`} />
      <CardHeader>
        <div className="flex items-center gap-4">
            <Icon className={`h-8 w-8 ${colorClass.replace('border-', 'text-')}`} />
            <div>
                <CardTitle>{title}</CardTitle>
                <CardDescription>{description}</CardDescription>
            </div>
        </div>
      </CardHeader>
      <CardContent>
        <p className="text-4xl font-bold">{formatCurrency(value)}</p>
        <p className="text-sm text-muted-foreground">in tied-up capital</p>
      </CardContent>
       <CardFooter>
        <Button asChild variant="secondary" className="w-full">
            <Link href={actionLink}>{actionText}</Link>
        </Button>
      </CardFooter>
    </Card>
  );
}


export default async function CashFlowPage() {
    const insights = await getCashFlowInsights();
    const totalCashTiedUp = insights.dead_stock_value + insights.slow_mover_value;

    return (
        <AppPage>
            <AppPageHeader
                title="Cash Flow Intelligence"
                description="Identify and unlock cash trapped in your inventory."
            />

            <Card className="bg-gradient-to-br from-primary/10 to-transparent">
                <CardHeader>
                     <CardTitle className="text-3xl text-primary">
                        {formatCurrency(totalCashTiedUp)}
                    </CardTitle>
                    <CardDescription>
                        Total recoverable cash currently tied up in non-performing inventory.
                    </CardDescription>
                </CardHeader>
            </Card>

            <div className="grid md:grid-cols-2 gap-6">
                 <MetricCard
                    title="Dead Stock"
                    value={insights.dead_stock_value}
                    icon={AlertCircle}
                    description={`Items unsold for over ${insights.dead_stock_threshold_days} days.`}
                    colorClass="border-destructive"
                    actionLink="/dead-stock"
                    actionText="View Dead Stock Report"
                />
                 <MetricCard
                    title="Slow Movers"
                    value={insights.slow_mover_value}
                    icon={Clock}
                    description={`Items unsold for 30-${insights.dead_stock_threshold_days} days.`}
                    colorClass="border-warning"
                    actionLink="/inventory?query=slow"
                    actionText="Investigate Slow Movers"
                />
            </div>
            
             <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <Bot className="h-5 w-5 text-primary"/>
                        Actionable Next Steps
                    </CardTitle>
                    <CardDescription>
                        Use InvoChat's AI to generate strategies for recovering this capital.
                    </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                     <div className="flex justify-between items-center p-3 bg-muted/50 rounded-lg">
                        <div>
                            <h4 className="font-semibold">Generate Liquidation Plan</h4>
                            <p className="text-sm text-muted-foreground">Create a markdown and promotion plan for dead stock items.</p>
                        </div>
                        <Button asChild>
                            <Link href="/chat?q=Create a liquidation plan for my dead stock">Ask AI</Link>
                        </Button>
                     </div>
                      <div className="flex justify-between items-center p-3 bg-muted/50 rounded-lg">
                        <div>
                            <h4 className="font-semibold">Suggest Bundles</h4>
                            <p className="text-sm text-muted-foreground">Ask for smart bundle ideas pairing slow-movers with best-sellers.</p>
                        </div>
                        <Button asChild>
                            <Link href="/chat?q=Suggest product bundles to move my slow-moving items">Ask AI</Link>
                        </Button>
                     </div>
                </CardContent>
            </Card>

        </AppPage>
    );
}