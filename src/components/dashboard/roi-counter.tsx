
'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { DollarSign, AlertTriangle, Clock, TrendingUp } from 'lucide-react';
import type { DashboardMetrics } from '@/types';
import { motion, useInView } from 'framer-motion';
import { useRef } from 'react';

interface RoiCounterProps {
    metrics: DashboardMetrics;
}

// Helper to format currency
function formatCurrency(value: number) {
    if (value < 0) {
        return `-$${Math.abs(value).toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`;
    }
    return `$${value.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`;
}


export function RoiCounter({ metrics }: RoiCounterProps) {
    const ref = useRef(null);
    const isInView = useInView(ref, { once: true, amount: 0.3 });

    // --- More realistic ROI Calculations ---
    // Estimated profit per average order (assuming 30% margin for this calculation)
    const avgProfitPerOrder = metrics.averageOrderValue * 0.3;

    // Value from preventing stockouts. Each low stock item is a potential stockout.
    const stockoutSavings = metrics.lowStockItemsCount * avgProfitPerOrder;
    
    // Value from addressing dead stock. Assumes we can recoup 25% of the tied-up capital.
    const deadStockValue = metrics.deadStockItemsCount > 0
        ? (metrics.totalInventoryValue / metrics.totalSkus) * metrics.deadStockItemsCount
        : 0;
    const deadStockSavings = deadStockValue * 0.25;

    // Placeholder for time saved. Could be made more dynamic in future.
    const timeSavedHours = 10;
    const timeValue = timeSavedHours * 25; // Assume $25/hr value of time

    const totalSavings = stockoutSavings + deadStockSavings + timeValue;

    return (
        <motion.div
            ref={ref}
            initial={{ opacity: 0, y: 50 }}
            animate={{ opacity: isInView ? 1 : 0, y: isInView ? 0 : 50 }}
            transition={{ duration: 0.8, ease: "easeOut" }}
            className="h-full"
        >
            <Card className="h-full bg-gradient-to-br from-emerald-500/10 to-green-500/10 border-emerald-500/20 flex flex-col">
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <TrendingUp className="h-5 w-5 text-success" />
                        Monthly Value Generated
                    </CardTitle>
                    <CardDescription>
                        Estimated savings powered by InvoChat's insights this month.
                    </CardDescription>
                </CardHeader>
                <CardContent className="flex-grow flex flex-col items-center justify-center text-center">
                    <p className="text-sm text-muted-foreground">You Saved an Estimated</p>
                    <p className="text-5xl font-bold text-success my-2">
                        {formatCurrency(totalSavings)}
                    </p>
                </CardContent>
                <CardContent className="space-y-3 text-sm">
                    <div className="flex justify-between items-center">
                        <span className="flex items-center gap-2 text-muted-foreground"><AlertTriangle className="h-4 w-4"/>Prevented Stockouts</span>
                        <span className="font-medium text-success">{formatCurrency(stockoutSavings)}</span>
                    </div>
                     <div className="flex justify-between items-center">
                        <span className="flex items-center gap-2 text-muted-foreground"><DollarSign className="h-4 w-4"/>Dead Stock Recovery</span>
                        <span className="font-medium text-success">{formatCurrency(deadStockSavings)}</span>
                    </div>
                     <div className="flex justify-between items-center">
                        <span className="flex items-center gap-2 text-muted-foreground"><Clock className="h-4 w-4"/>Time Saved</span>
                        <span className="font-medium text-success">{timeSavedHours} Hours</span>
                    </div>
                </CardContent>
            </Card>
        </motion.div>
    );
}
