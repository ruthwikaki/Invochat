
'use client';

import { useState, useTransition } from 'react';
import { useRouter, usePathname, useSearchParams } from 'next/navigation';
import { useDebouncedCallback } from 'use-debounce';
import { Input } from '@/components/ui/input';
import type { Customer } from '@/types';
import { Card, CardContent } from '@/components/ui/card';
import { Search, MoreHorizontal, Trash2, Loader2, Users } from 'lucide-react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Button } from '@/components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { motion } from 'framer-motion';
import {
  AlertDialog,
  AlertDialogTrigger,
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
import { Avatar, AvatarFallback } from '../ui/avatar';
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf';

interface CustomersClientPageProps {
  initialCustomers: Customer[];
  totalCount: number;
  itemsPerPage: number;
}

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

export function CustomersClientPage({ initialCustomers, totalCount, itemsPerPage }: CustomersClientPageProps) {
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
      const csrfToken = getCookie('csrf_token');
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
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search by customer name or email..."
            onChange={(e) => handleSearch(e.target.value)}
            defaultValue={searchParams.get('query')?.toString()}
            className="pl-10"
          />
        </div>
      </div>

      <AlertDialog open={!!customerToDelete} onOpenChange={(open) => !open && setCustomerToDelete(null)}>
        <AlertDialogContent>
            <AlertDialogHeader>
                <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
                <AlertDialogDescription>
                    This will permanently delete {customerToDelete?.customer_name}. If the customer has existing orders, their record will be preserved but marked as deleted (soft-delete). This action cannot be undone.
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

      {showEmptyState ? <EmptyCustomerState /> : (
        <Card>
          <CardContent className="p-0">
            <div className="max-h-[65vh] overflow-auto">
              <Table>
                <TableHeader className="sticky top-0 z-10 bg-background/80 backdrop-blur-sm">
                  <TableRow>
                    <TableHead>Customer</TableHead>
                    <TableHead className="text-right">Total Orders</TableHead>
                    <TableHead className="text-right">Total Spend</TableHead>
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
                                <AvatarFallback>{customer.customer_name.charAt(0)}</AvatarFallback>
                            </Avatar>
                            <div>
                                <div className="font-medium">{customer.customer_name}</div>
                                <div className="text-xs text-muted-foreground">{customer.email}</div>
                            </div>
                        </div>
                      </TableCell>
                      <TableCell className="text-right">{customer.total_orders}</TableCell>
                      <TableCell className="text-right font-medium">${customer.total_spend.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</TableCell>
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
          </CardContent>
        </Card>
      )}
    </div>
  );
}
