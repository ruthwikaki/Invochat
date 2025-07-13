

'use client';

import { useRouter, usePathname, useSearchParams } from 'next/navigation';
import { useDebouncedCallback } from 'use-debounce';
import type { Order, SalesAnalytics } from '@/types';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Search, Plus, ShoppingCart, Download, DollarSign, BarChart } from 'lucide-react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { motion } from 'framer-motion';
import { Input } from '../ui/input';
import Link from 'next/link';
import { ExportButton } from '../ui/export-button';
import { ResponsiveContainer, PieChart, Pie, Cell, Tooltip } from 'recharts';
import { formatCentsAsCurrency } from '@/lib/utils';

interface SalesClientPageProps {
  initialSales: Order[];
  totalCount: number;
  itemsPerPage: number;
  analyticsData: SalesAnalytics;
  exportAction: () => Promise<{ success: boolean; data?: string; error?: string }>;
}

const AnalyticsCard = ({ title, value, icon: Icon, label }: { title: string, value: string | number, icon: React.ElementType, label?: string }) => (
    <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
            <Icon className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
            <div className="text-2xl font-bold">{typeof value === 'number' && !Number.isInteger(value) ? formatCentsAsCurrency(value) : value}</div>
            {label && <p className="text-xs text-muted-foreground">{label}</p>}
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

    if (totalPages <= 1) { return null; }

    return (
        <div className="flex items-center justify-between p-4 border-t">
            <p className="text-sm text-muted-foreground">Showing page <strong>{currentPage}</strong> of <strong>{totalPages}</strong> ({totalCount} sales)</p>
            <div className="flex items-center gap-2">
                <Button variant="outline" onClick={() => router.push(createPageURL(currentPage - 1))} disabled={currentPage <= 1}>Previous</Button>
                <Button variant="outline" onClick={() => router.push(createPageURL(currentPage + 1))} disabled={currentPage >= totalPages}>Next</Button>
            </div>
        </div>
    );
};

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
      </motion.div>
      <h3 className="mt-6 text-xl font-semibold">No Sales Recorded Yet</h3>
      <p className="mt-2 text-muted-foreground">Your sales from connected stores will appear here after the first sync.</p>
      <Button asChild className="mt-6"><Link href="/settings/integrations">Connect a Store</Link></Button>
    </Card>
  );
}

export function SalesClientPage({ initialSales, totalCount, itemsPerPage, analyticsData, exportAction }: SalesClientPageProps) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

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
  
  const showEmptyState = totalCount === 0 && !searchParams.get('query');
  const showNoResultsState = totalCount === 0 && searchParams.get('query');

  return (
    <div className="space-y-6">
       <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            <AnalyticsCard title="Total Revenue" value={formatCentsAsCurrency(analyticsData.total_revenue)} icon={DollarSign} />
            <AnalyticsCard title="Average Sale Value" value={formatCentsAsCurrency(analyticsData.average_sale_value)} icon={BarChart} />
        </div>
      <div className="flex items-center justify-between gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input placeholder="Search by order #, customer name or email..." onChange={(e) => handleSearch(e.target.value)} defaultValue={searchParams.get('query')?.toString()} className="pl-10"/>
        </div>
        <ExportButton exportAction={exportAction} filename="sales.csv" />
      </div>

      {showEmptyState ? <EmptySalesState /> : (
        <Card>
          <CardContent className="p-0">
            <div className="max-h-[65vh] overflow-auto">
              <Table>
                <TableHeader className="sticky top-0 z-10 bg-background/80 backdrop-blur-sm">
                  <TableRow>
                    <TableHead>Order</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead>Financial Status</TableHead>
                    <TableHead>Fulfillment Status</TableHead>
                    <TableHead className="text-right">Total</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {showNoResultsState ? (
                    <TableRow><TableCell colSpan={5} className="h-24 text-center">No sales found matching your search.</TableCell></TableRow>
                  ) : initialSales.map(order => (
                    <TableRow key={order.id} className="hover:shadow-md transition-shadow cursor-pointer">
                      <TableCell className="font-medium">{order.order_number}</TableCell>
                      <TableCell>{format(new Date(order.created_at), 'PP p')}</TableCell>
                      <TableCell><Badge variant="outline" className="capitalize">{order.financial_status?.replace(/_/g, ' ')}</Badge></TableCell>
                       <TableCell><Badge variant="outline" className="capitalize">{order.fulfillment_status?.replace(/_/g, ' ')}</Badge></TableCell>
                      <TableCell className="text-right">{formatCentsAsCurrency(order.total_amount)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
            <PaginationControls totalCount={totalCount} itemsPerPage={itemsPerPage} />
          </CardContent>
        </Card>
      )}
    </div>
  );
}
