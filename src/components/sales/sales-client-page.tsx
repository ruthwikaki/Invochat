
'use client';

import { useRouter, usePathname, useSearchParams } from 'next/navigation';
import { useDebouncedCallback } from 'use-debounce';
import { Input } from '@/components/ui/input';
import type { Order, SalesAnalytics } from '@/types';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Search, DollarSign, ShoppingCart, Percent, Users } from 'lucide-react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { cn } from '@/lib/utils';
import { formatCentsAsCurrency } from '@/lib/utils';
import { ExportButton } from '../ui/export-button';
import { Button } from '../ui/button';

interface SalesClientPageProps {
  initialSales: Order[];
  totalCount: number;
  itemsPerPage: number;
  analyticsData: SalesAnalytics;
  exportAction: (params: { query: string }) => Promise<{ success: boolean; data?: string; error?: string }>;
}

const AnalyticsCard = ({ title, value, icon: Icon, prefix = '', suffix = '' }: { title: string, value: string | number, icon: React.ElementType, prefix?: string, suffix?: string }) => (
    <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
            <Icon className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
            <div className="text-2xl font-bold font-tabular">{prefix}{value}{suffix}</div>
        </CardContent>
    </Card>
);

const PaginationControls = ({ totalCount, itemsPerPage }: { totalCount: number, itemsPerPage: number }) => {
    const router = useRouter();
    const pathname = usePathname();
    const searchParams = useSearchParams();
    const currentPage = Number(searchParams.get('page')) || 1;
    const totalPages = Math.ceil(totalCount / itemsPerPage);

    const createPageURL = (pageNumber: number | string) => {
        const params = new URLSearchParams(searchParams);
        params.set('page', pageNumber.toString());
        return `${pathname}?${params.toString()}`;
    };

    if (totalPages <= 1) {
        return null;
    }

    return (
        <div className="flex items-center justify-between p-4 border-t">
            <p className="text-sm text-muted-foreground">
                Showing page <strong>{currentPage}</strong> of <strong>{totalPages}</strong> ({totalCount} orders)
            </p>
            <div className="flex items-center gap-2">
                <Button
                    variant="outline"
                    onClick={() => router.push(createPageURL(currentPage - 1))}
                    disabled={currentPage <= 1}
                >
                    Previous
                </Button>
                <Button
                    variant="outline"
                    onClick={() => router.push(createPageURL(currentPage + 1))}
                    disabled={currentPage >= totalPages}
                >
                    Next
                </Button>
            </div>
        </div>
    );
};


export function SalesClientPage({ initialSales, totalCount, itemsPerPage, analyticsData, exportAction }: SalesClientPageProps) {
    const router = useRouter();
    const pathname = usePathname();
    const searchParams = useSearchParams();
    const query = searchParams.get('query') || '';

    const handleSearch = useDebouncedCallback((term: string) => {
        const params = new URLSearchParams(searchParams);
        params.set('page', '1');
        if (term) {
            params.set('query', term);
        } else {
            params.delete('query');
        }
        router.replace(`${pathname}?${params.toString()}`);
    }, 300);

    const handleExport = () => {
        return exportAction({ query });
    }

    const getFulfillmentBadge = (status: string | null) => {
        switch (status?.toLowerCase()) {
            case 'fulfilled':
                return <Badge variant="secondary" className="bg-success/10 text-success-foreground border-success/20">Fulfilled</Badge>;
            case 'partial':
                return <Badge variant="secondary" className="bg-warning/10 text-amber-600 dark:text-amber-400 border-warning/20">Partial</Badge>;
            case 'unfulfilled':
                return <Badge variant="outline">Unfulfilled</Badge>;
            default:
                return <Badge variant="outline">{status}</Badge>;
        }
    };
    
    return (
        <div className="space-y-6">
            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                <AnalyticsCard title="Total Revenue" value={formatCentsAsCurrency(analyticsData.total_revenue)} icon={DollarSign} />
                <AnalyticsCard title="Total Orders" value={analyticsData.total_orders.toLocaleString()} icon={ShoppingCart} />
                <AnalyticsCard title="Average Order Value" value={formatCentsAsCurrency(analyticsData.average_order_value)} icon={DollarSign} />
                <AnalyticsCard title="Average Margin" value={analyticsData.average_margin.toFixed(1)} suffix="%" icon={Percent} />
            </div>

            <Card>
                <CardHeader>
                    <div className="flex items-start justify-between">
                        <div>
                            <CardTitle>Sales Orders</CardTitle>
                            <CardDescription>A log of all sales from your connected platforms.</CardDescription>
                        </div>
                        <ExportButton exportAction={handleExport} filename="sales_orders.csv" />
                    </div>
                     <div className="relative pt-2">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                        <Input
                            placeholder="Search by order number or customer email..."
                            onChange={(e) => handleSearch(e.target.value)}
                            defaultValue={query}
                            className="pl-10"
                        />
                    </div>
                </CardHeader>
                <CardContent className="p-0">
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Order #</TableHead>
                                <TableHead>Date</TableHead>
                                <TableHead>Customer</TableHead>
                                <TableHead>Status</TableHead>
                                <TableHead className="text-right">Total</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {initialSales.length === 0 ? (
                                <TableRow>
                                    <TableCell colSpan={5} className="h-24 text-center">
                                        No sales orders found.
                                    </TableCell>
                                </TableRow>
                            ) : initialSales.map(order => (
                                <TableRow key={order.id}>
                                    <TableCell className="font-medium">{order.order_number}</TableCell>
                                    <TableCell>{format(new Date(order.created_at), 'MMM d, yyyy')}</TableCell>
                                    <TableCell>{order.customer_email || 'N/A'}</TableCell>
                                    <TableCell>{getFulfillmentBadge(order.fulfillment_status)}</TableCell>
                                    <TableCell className="text-right font-tabular">{formatCentsAsCurrency(order.total_amount)}</TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                    <PaginationControls totalCount={totalCount} itemsPerPage={itemsPerPage} />
                </CardContent>
            </Card>
        </div>
    )
}

    