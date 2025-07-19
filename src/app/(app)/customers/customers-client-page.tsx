

'use client';

import { useState, useTransition } from 'react';
import { useRouter, usePathname, useSearchParams } from 'next/navigation';
import { useDebouncedCallback } from 'use-debounce';
import { Input } from '@/components/ui/input';
import type { Customer, CustomerAnalytics } from '@/types';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Search, MoreHorizontal, Trash2, Loader2, Users, DollarSign, Repeat, UserPlus, ShoppingBag, Trophy, Star, Download } from 'lucide-react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Button } from '@/components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { motion } from 'framer-motion';
import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogCancel,
  AlertDialogAction
} from '@/components/ui/alert-dialog';
import { deleteCustomer } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf';
import { ExportButton } from '@/components/ui/export-button';

interface CustomersClientPageProps {
  initialCustomers: Customer[];
  totalCount: number;
  itemsPerPage: number;
  analyticsData: CustomerAnalytics;
  exportAction: () => Promise<{ success: boolean; data?: string; error?: string }>;
}

const formatCurrency = (value: number) => {
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD',
        minimumFractionDigits: 0,
        maximumFractionDigits: 0,
    }).format(value);
};

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

const TopCustomerList = ({ title, data, icon: Icon, valueLabel }: { title: string, data: { name: string, value: number }[], icon: React.ElementType, valueLabel: string }) => (
    <Card className="flex-1">
        <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
                <Icon className="h-5 w-5 text-primary" />
                {title}
            </CardTitle>
        </CardHeader>
        <CardContent>
            <ul className="space-y-3">
                {data.map((customer, index) => (
                    <li key={index} className="flex items-center justify-between text-sm">
                        <span className="font-medium truncate pr-4">{customer.name}</span>
                        <span className="font-semibold text-muted-foreground">{valueLabel === 'orders' ? customer.value : formatCurrency(customer.value)}</span>
                    </li>
                ))}
            </ul>
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
                Showing page <strong>{currentPage}</strong> of <strong>{totalPages}</strong> ({totalCount} customers)
            </p>
            <div className="flex items-center gap-2">
                <Button
                    variant="outline"
                    onClick={() => { router.push(createPageURL(currentPage - 1)); }}
                    disabled={currentPage <= 1}
                >
                    Previous
                </Button>
                <Button
                    variant="outline"
                    onClick={() => { router.push(createPageURL(currentPage + 1)); }}
                    disabled={currentPage >= totalPages}
                >
                    Next
                </Button>
            </div>
        </div>
    );
};

function EmptyCustomerState() {
  return (
    <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
        className="relative bg-primary/10 rounded-full p-6"
      >
        <Users className="h-16 w-16 text-primary" />
      </motion.div>
      <h3 className="mt-6 text-xl font-semibold">No Customers Found</h3>
      <p className="mt-2 text-muted-foreground">
        Your customers will appear here as they make purchases through your integrations.
      </p>
    </Card>
  );
}

export function CustomersClientPage({ initialCustomers, totalCount, itemsPerPage, analyticsData, exportAction }: CustomersClientPageProps) {
  const [isDeleting, startDeleteTransition] = useTransition();
  const [customerToDelete, setCustomerToDelete] = useState<Customer | null>(null);
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { toast } = useToast();

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

  const handleDelete = () => {
    if (!customerToDelete) return;
    startDeleteTransition(async () => {
      const formData = new FormData();
      formData.append('id', customerToDelete.id);
      const csrfToken = getCookie(CSRF_FORM_NAME);
      if (csrfToken) {
          formData.append(CSRF_FORM_NAME, csrfToken);
      }

      const result = await deleteCustomer(formData);
      if (result.success) {
        toast({ title: "Customer Deleted", description: `Customer ${customerToDelete.customer_name} has been removed.` });
        router.refresh();
      } else {
        toast({ variant: 'destructive', title: "Error Deleting Customer", description: result.error });
      }
      setCustomerToDelete(null);
    });
  };

  return (
    <div className="space-y-6">
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            <AnalyticsCard title="Total Customers" value={analyticsData.total_customers.toLocaleString()} icon={Users} />
            <AnalyticsCard title="Avg. Lifetime Value" value={formatCurrency(analyticsData.average_lifetime_value)} icon={DollarSign} />
            <AnalyticsCard title="New Customers (30d)" value={analyticsData.new_customers_last_30_days.toLocaleString()} icon={UserPlus} />
            <AnalyticsCard title="Repeat Customer Rate" value={`${(analyticsData.repeat_customer_rate * 100).toFixed(1)}%`} icon={Repeat} />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <TopCustomerList title="Top Customers by Spend" data={analyticsData.top_customers_by_spend} icon={Trophy} valueLabel="spend" />
            <TopCustomerList title="Top Customers by Sales" data={analyticsData.top_customers_by_sales} icon={ShoppingBag} valueLabel="orders" />
        </div>

        <Card>
            <CardHeader>
                <div className="flex items-start justify-between">
                  <div>
                    <CardTitle>All Customers</CardTitle>
                    <CardDescription>Search and manage your complete customer list.</CardDescription>
                  </div>
                  <ExportButton exportAction={exportAction} filename="customers.csv" />
                </div>
                <div className="relative pt-2">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                    <Input
                        placeholder="Search by customer name or email..."
                        onChange={(e) => handleSearch(e.target.value)}
                        defaultValue={searchParams.get('query')?.toString()}
                        className="pl-10"
                    />
                </div>
            </CardHeader>
            <CardContent className="p-0">
                {showEmptyState ? <EmptyCustomerState /> : (
                    <>
                    <div className="max-h-[65vh] overflow-auto">
                    <Table>
                        <TableHeader className="sticky top-0 z-10 bg-background/80 backdrop-blur-sm">
                        <TableRow>
                            <TableHead>Customer</TableHead>
                            <TableHead className="text-right">Total Orders</TableHead>
                            <TableHead className="text-right">Total Spent</TableHead>
                            <TableHead className="w-16 text-center">Actions</TableHead>
                        </TableRow>
                        </TableHeader>
                        <TableBody>
                        {showNoResultsState ? (
                            <TableRow>
                            <TableCell colSpan={4} className="h-24 text-center">
                                No customers found matching your search.
                            </TableCell>
                            </TableRow>
                        ) : initialCustomers.map(customer => (
                            <TableRow key={customer.id} className="hover:shadow-md transition-shadow">
                            <TableCell>
                                <div className="flex items-center gap-3">
                                    <Avatar className="h-9 w-9">
                                        <AvatarFallback>{customer.customer_name?.charAt(0) || '?'}</AvatarFallback>
                                    </Avatar>
                                    <div>
                                        <div className="font-medium">{customer.customer_name}</div>
                                        <div className="text-xs text-muted-foreground">{customer.email}</div>
                                    </div>
                                </div>
                            </TableCell>
                            <TableCell className="text-right">{customer.total_orders}</TableCell>
                            <TableCell className="text-right font-medium">${(customer.total_spent / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</TableCell>
                            <TableCell className="text-center">
                                <DropdownMenu>
                                    <DropdownMenuTrigger asChild onClick={(e) => e.stopPropagation()}>
                                        <Button variant="ghost" size="icon" className="h-8 w-8">
                                            <MoreHorizontal className="h-4 w-4" />
                                        </Button>
                                    </DropdownMenuTrigger>
                                    <DropdownMenuContent align="end">
                                        <DropdownMenuItem onSelect={(e) => {e.preventDefault(); setCustomerToDelete(customer);}} className="text-destructive"><Trash2 className="mr-2 h-4 w-4"/>Delete Customer</DropdownMenuItem>
                                    </DropdownMenuContent>
                                </DropdownMenu>
                            </TableCell>
                            </TableRow>
                        ))}
                        </TableBody>
                    </Table>
                    </div>
                    <PaginationControls totalCount={totalCount} itemsPerPage={itemsPerPage} />
                </>
                )}
            </CardContent>
        </Card>

      <AlertDialog open={!!customerToDelete} onOpenChange={(open) => { if (!open) setCustomerToDelete(null); }}>
        <AlertDialogContent>
            <AlertDialogHeader>
                <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
                <AlertDialogDescription>
                    This will permanently delete {customerToDelete?.customer_name || 'this customer'}. If the customer has existing orders, their record will be preserved but marked as deleted (soft-delete). This action cannot be undone.
                </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
                <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
                <AlertDialogAction onClick={handleDelete} disabled={isDeleting} className="bg-destructive hover:bg-destructive/90">
                    {isDeleting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Yes, delete
                </AlertDialogAction>
            </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
