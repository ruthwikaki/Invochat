
'use client';

import { Input } from '@/components/ui/input';
import type { Order, SalesAnalytics } from '@/types';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Search, DollarSign, ShoppingCart, Percent, Sparkles } from 'lucide-react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { formatCentsAsCurrency } from '@/lib/utils';
import { ExportButton } from '@/components/ui/export-button';
import { Button } from '@/components/ui/button';
import { useTableState } from '@/hooks/use-table-state';
import { motion } from 'framer-motion';
import Link from 'next/link';

interface SalesClientPageProps {
  initialSales: Order[];
  totalCount: number;
  itemsPerPage: number;
  analyticsData: SalesAnalytics;
  exportAction: (params: { query: string }) => Promise<{ success: boolean; data?: string; error?: string }>;
}

function EmptySalesState() {
  return (
    <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
        className="relative bg-primary/10 rounded-full p-6"
      >
        <ShoppingCart className="h-16 w-16 text-primary" />
         <motion.div
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.4, duration: 0.5 }}
          className="absolute -top-2 -right-2 text-primary"
        >
          <Sparkles className="h-8 w-8" />
        </motion.div>
      </motion.div>
      <h3 className="mt-6 text-xl font-semibold">No Sales Data Yet</h3>
      <p className="mt-2 text-muted-foreground">
        Your sales will appear here once you connect an integration and sync your data.
      </p>
       <Button asChild className="mt-6">
        <Link href="/settings/integrations">Connect an Integration</Link>
      </Button>
    </Card>
  );
}

const AnalyticsCard = ({ title, value, icon: Icon }: { title: string, value: string, icon: React.ElementType }) => (
    <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
            <Icon className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
            <div className="text-2xl font-bold">{value}</div>
        </CardContent>
    </Card>
);

const PaginationControls = ({ totalCount, itemsPerPage, currentPage, onPageChange }: { totalCount: number; itemsPerPage: number; currentPage: number, onPageChange: (page: number) => void }) => {
    const totalPages = Math.ceil(totalCount / itemsPerPage);

    if (totalPages <= 1) {
        return null;
    }

    return (
        <div className="flex items-center justify-between p-4 border-t">
            <p className="text-sm text-muted-foreground">
                Showing page <strong>{currentPage}</strong> of <strong>{totalPages}</strong> ({totalCount} sales)
            </p>
            <div className="flex items-center gap-2">
                <Button
                    variant="outline"
                    onClick={() => onPageChange(currentPage - 1)}
                    disabled={currentPage <= 1}
                >
                    Previous
                </Button>
                <Button
                    variant="outline"
                    onClick={() => onPageChange(currentPage + 1)}
                    disabled={currentPage >= totalPages}
                >
                    Next
                </Button>
            </div>
        </div>
    );
};


export function SalesClientPage({ initialSales, totalCount, itemsPerPage, analyticsData, exportAction }: SalesClientPageProps) {
    const {
        searchQuery,
        page,
        handleSearch,
        handlePageChange
    } = useTableState({ defaultSortColumn: 'created_at' });

    const handleExport = () => {
        return exportAction({ query: searchQuery });
    }

    if(totalCount === 0 && !searchQuery) {
        return <EmptySalesState />;
    }

    return (
    <div className="space-y-6">
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            <AnalyticsCard title="Total Revenue" value={formatCentsAsCurrency(analyticsData.total_revenue)} icon={DollarSign} />
            <AnalyticsCard title="Total Orders" value={analyticsData.total_orders.toLocaleString()} icon={ShoppingCart} />
            <AnalyticsCard title="Average Order Value" value={formatCentsAsCurrency(analyticsData.average_order_value)} icon={Percent} />
        </div>
        
        <Card>
            <CardHeader>
                <div className="flex items-start justify-between">
                    <div>
                        <CardTitle>Sales History</CardTitle>
                        <CardDescription>A complete log of all recorded sales orders.</CardDescription>
                    </div>
                     <ExportButton exportAction={handleExport} filename="sales_orders.csv" />
                </div>
                <div className="relative pt-2">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                    <Input
                        placeholder="Search by order number or customer email..."
                        onChange={(e) => handleSearch(e.target.value)}
                        defaultValue={searchQuery}
                        className="pl-10"
                    />
                </div>
            </CardHeader>
            <CardContent className="p-0">
                <div className="max-h-[65vh] overflow-auto">
                    <Table>
                        <TableHeader className="sticky top-0 z-10 bg-background/80 backdrop-blur-sm">
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
                                No sales orders found matching your search.
                            </TableCell>
                            </TableRow>
                        ) : initialSales.map(order => (
                            <TableRow key={order.id}>
                                <TableCell className="font-medium">{order.order_number}</TableCell>
                                <TableCell>{format(new Date(order.created_at), 'MMM d, yyyy')}</TableCell>
                                <TableCell>{order.customer_email || 'N/A'}</TableCell>
                                <TableCell>
                                    <Badge variant={order.financial_status === 'paid' ? 'secondary' : 'outline'}>{order.financial_status || 'N/A'}</Badge>
                                </TableCell>
                                <TableCell className="text-right font-medium">{formatCentsAsCurrency(order.total_amount)}</TableCell>
                            </TableRow>
                        ))}
                        </TableBody>
                    </Table>
                </div>
                 <PaginationControls totalCount={totalCount} itemsPerPage={itemsPerPage} currentPage={page} onPageChange={handlePageChange} />
            </CardContent>
        </Card>
    </div>
  );
}
