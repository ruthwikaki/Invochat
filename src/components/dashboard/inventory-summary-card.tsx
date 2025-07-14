
'use client';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { formatCentsAsCurrency } from '@/lib/utils';
import Link from 'next/link';

interface InventorySummaryCardProps {
    data: {
        total_value: number;
        in_stock_value: number;
        low_stock_value: number;
        dead_stock_value: number;
    };
}

const SummaryItem = ({ label, value, colorClass, link }: { label: string; value: number; colorClass: string; link?: string }) => (
    <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
            <span className={`h-2 w-2 rounded-full ${colorClass}`}></span>
            {link ? (
                <Link href={link} className="text-sm text-muted-foreground hover:text-primary underline-offset-2 hover:underline">
                    {label}
                </Link>
            ) : (
                <span className="text-sm text-muted-foreground">{label}</span>
            )}
        </div>
        <span className="font-medium text-sm">{formatCentsAsCurrency(value)}</span>
    </div>
);

export function InventorySummaryCard({ data }: InventorySummaryCardProps) {
    const totalValue = data.total_value;
    const inStockPercentage = totalValue > 0 ? (data.in_stock_value / totalValue) * 100 : 0;
    const lowStockPercentage = totalValue > 0 ? (data.low_stock_value / totalValue) * 100 : 0;
    const deadStockPercentage = totalValue > 0 ? (data.dead_stock_value / totalValue) * 100 : 0;

    return (
        <Card>
            <CardHeader>
                <CardTitle>Inventory Value Summary</CardTitle>
                <CardDescription>
                    A breakdown of your total inventory value by stock status.
                </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
                <div className="relative h-4 w-full rounded-full bg-muted overflow-hidden">
                    <div className="absolute h-full bg-success" style={{ width: `${inStockPercentage}%`, zIndex: 30 }}></div>
                    <div className="absolute h-full bg-warning" style={{ width: `${lowStockPercentage}%`, left: `${inStockPercentage}%`, zIndex: 20 }}></div>
                    <div className="absolute h-full bg-destructive" style={{ width: `${deadStockPercentage}%`, left: `${inStockPercentage + lowStockPercentage}%`, zIndex: 10 }}></div>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <SummaryItem label="Healthy Stock" value={data.in_stock_value} colorClass="bg-success" />
                    <SummaryItem label="Low Stock" value={data.low_stock_value} colorClass="bg-warning" link="/reordering" />
                    <SummaryItem label="Dead Stock" value={data.dead_stock_value} colorClass="bg-destructive" link="/dead-stock" />
                </div>
            </CardContent>
        </Card>
    );
}
