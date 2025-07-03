
'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { motion, useInView } from 'framer-motion';
import { useRef } from 'react';
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts';
import type { DashboardMetrics } from '@/types';
import { cn } from '@/lib/utils';
import { AlertCircle, CheckCircle, ShieldQuestion, TrendingUp, Sparkles, AlertTriangle, ArrowRight } from 'lucide-react';
import { linearRegression } from '@/lib/utils';
import { Button } from '../ui/button';
import Link from 'next/link';

type BusinessHealthScoreProps = {
  metrics: DashboardMetrics;
};

// Simplified calculation based on the user's idea
const calculateHealthScore = (metrics: DashboardMetrics) => {
    const scores = {
        inventory: 0,
        profitability: 0,
        stockAvailability: 0,
        salesGrowth: 0,
    };

    // Inventory Health (25 points): Based on dead stock ratio
    const deadStockRatio = metrics.totalSkus > 0 ? metrics.deadStockItemsCount / metrics.totalSkus : 0;
    scores.inventory = Math.max(0, (1 - deadStockRatio * 2) * 25); // Penalize dead stock more heavily

    // Profitability (25 points): Based on gross margin
    const margin = metrics.totalSalesValue > 0 ? (metrics.totalProfit / metrics.totalSalesValue) * 100 : 0;
    if (margin > 30) scores.profitability = 25;
    else if (margin > 15) scores.profitability = 15;
    else scores.profitability = 5;

    // Stock Availability (25 points): Based on low stock ratio
    const lowStockRatio = metrics.totalSkus > 0 ? metrics.lowStockItemsCount / metrics.totalSkus : 0;
    scores.stockAvailability = Math.max(0, (1 - lowStockRatio) * 25);
    
    // Sales Growth (25 points): Based on sales trend
    if (metrics.salesTrendData.length > 1) {
        const trendData = metrics.salesTrendData.map((d, i) => ({ x: i, y: d.Sales }));
        const { slope } = linearRegression(trendData);
        scores.salesGrowth = slope > 0 ? 25 : 10;
    } else {
        scores.salesGrowth = 15; // Neutral score if not enough data
    }
    
    const total = Math.round(Object.values(scores).reduce((a, b) => a + b, 0));
    return {
        total,
        breakdown: scores
    };
};

function ScoreIndicator({ Icon, score, label, actionLink, actionLabel }: { Icon: React.ElementType, score: number, label: string, actionLink: string, actionLabel: string }) {
    const colorClass = score > 18 ? "text-success" : score > 10 ? "text-amber-500" : "text-destructive";
    return (
        <div className="flex items-center justify-between gap-2 text-sm p-2 rounded-lg hover:bg-muted/50 transition-colors">
            <div className="flex items-center gap-2">
                <Icon className={cn("h-4 w-4", colorClass)} />
                <span className="text-muted-foreground">{label}:</span>
                <span className={cn("font-semibold", colorClass)}>{score.toFixed(0)}/25</span>
            </div>
            <Button asChild variant="ghost" size="sm" className="h-7 text-xs">
                <Link href={actionLink}>
                    {actionLabel} <ArrowRight className="ml-1 h-3 w-3" />
                </Link>
            </Button>
        </div>
    )
}

export function BusinessHealthScore({ metrics }: BusinessHealthScoreProps) {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, amount: 0.3 });
  const { total, breakdown } = calculateHealthScore(metrics);

  const data = [
    { name: 'Score', value: total },
    { name: 'Remaining', value: 100 - total },
  ];

  const scoreColor = total > 80 ? 'hsl(var(--success))' : total > 60 ? 'hsl(var(--warning))' : 'hsl(var(--destructive))';
  
  const scoreLabel = total > 80 ? 'Excellent' : total > 60 ? 'Good' : 'Needs Attention';

  return (
    <motion.div
      ref={ref}
      initial={{ opacity: 0, y: 50 }}
      animate={{ opacity: isInView ? 1 : 0, y: isInView ? 0 : 50 }}
      transition={{ duration: 0.8, ease: "easeOut" }}
    >
      <Card className="h-full flex flex-col">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Sparkles className="h-5 w-5 text-primary" />
            Business Health Score
          </CardTitle>
          <CardDescription>An AI-powered overview of your key metrics with actionable links.</CardDescription>
        </CardHeader>
        <CardContent className="flex-grow flex flex-col md:flex-row items-center justify-center gap-6">
          <div className="relative h-48 w-48">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Tooltip
                  cursor={false}
                  contentStyle={{ display: 'none' }}
                />
                <Pie
                  data={data}
                  cx="50%"
                  cy="50%"
                  dataKey="value"
                  innerRadius={60}
                  outerRadius={80}
                  startAngle={90}
                  endAngle={-270}
                  paddingAngle={0}
                  isAnimationActive={isInView}
                  animationDuration={1500}
                >
                  <Cell key="score" fill={scoreColor} stroke={scoreColor} />
                  <Cell key="remaining" fill="hsl(var(--muted))" stroke="hsl(var(--muted))" />
                </Pie>
              </PieChart>
            </ResponsiveContainer>
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <span className="text-4xl font-bold" style={{ color: scoreColor }}>{total}</span>
              <span className="text-sm font-medium" style={{ color: scoreColor }}>{scoreLabel}</span>
            </div>
          </div>
          <div className="space-y-1 self-stretch flex-1">
              <ScoreIndicator Icon={CheckCircle} score={breakdown.profitability} label="Profitability" actionLink="/analytics" actionLabel="View Reports" />
              <ScoreIndicator Icon={TrendingUp} score={breakdown.salesGrowth} label="Sales Growth" actionLink="/dashboard" actionLabel="View Trend" />
              <ScoreIndicator Icon={AlertTriangle} score={breakdown.stockAvailability} label="Stock Availability" actionLink="/reordering" actionLabel="Get Suggestions" />
              <ScoreIndicator Icon={ShieldQuestion} score={breakdown.inventory} label="Inventory Health" actionLink="/dead-stock" actionLabel="View Dead Stock" />
          </div>
        </CardContent>
      </Card>
    </motion.div>
  );
}
