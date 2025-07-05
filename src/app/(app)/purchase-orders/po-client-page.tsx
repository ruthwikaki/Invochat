
'use client';

import { useState, useTransition } from 'react';
import Link from 'next/link';
import { useRouter, usePathname, useSearchParams } from 'next/navigation';
import { useDebouncedCallback } from 'use-debounce';
import { Input } from '@/components/ui/input';
import type { PurchaseOrder } from '@/types';
import { Card, CardContent } from '@/components/ui/card';
import { Search, MoreHorizontal, Plus, PackagePlus, Edit, Trash2, Loader2 } from 'lucide-react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { motion } from 'framer-motion';
import { format } from 'date-fns';
import { AlertDialog, AlertDialogTrigger, AlertDialogContent, AlertDialogHeader, AlertDialogTitle, AlertDialogDescription, AlertDialogFooter, AlertDialogCancel, AlertDialogAction } from '@/components/ui/alert-dialog';
import { deletePurchaseOrder } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf';

interface PurchaseOrderClientPageProps {
  initialPurchaseOrders: PurchaseOrder[];
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


const getStatusVariant = (status: PurchaseOrder['status']) => {
  if (!status) return 'outline';
  switch (status) {
    case 'draft':
      return 'outline';
    case 'sent':
      return 'secondary';
    case 'partial':
       return 'default';
    case 'received':
      return 'default';
    case 'cancelled':
      return 'destructive';
    default:
      return 'outline';
  }
};

const getStatusColor = (status: PurchaseOrder['status']) => {
  if (!status) return 'border-gray-400 text-gray-500';
  switch (status) {
    case 'draft':
      return 'border-gray-400 text-gray-500';
    case 'sent':
      return 'bg-blue-500/10 text-blue-600 border-blue-500/20';
    case 'partial':
       return 'bg-yellow-500/10 text-yellow-600 border-yellow-500/20';
    case 'received':
      return 'bg-success/10 text-emerald-600 border-success/20';
    case 'cancelled':
      return 'bg-destructive/10 text-destructive border-destructive/20';
    default:
      return '';
  }
};


function EmptyPOState() {
  return (
    <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
        className="relative bg-primary/10 rounded-full p-6"
      >
        <PackagePlus className="h-16 w-16 text-primary" />
      </motion.div>
      <h3 className="mt-6 text-xl font-semibold">No Purchase Orders Yet</h3>
      <p className="mt-2 text-muted-foreground">
        Create your first purchase order to start tracking incoming inventory.
      </p>
      <Button asChild className="mt-6">
        <Link href="/purchase-orders/new">Create New PO</Link>
      </Button>
    </Card>
  );
}

export function PurchaseOrderClientPage({ initialPurchaseOrders, totalCount, itemsPerPage }: PurchaseOrderClientPageProps) {
  const [isDeleting, startDeleteTransition] = useTransition();
  const [poToDelete, setPoToDelete] = useState<PurchaseOrder | null>(null);
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
    if (!poToDelete) return;
    startDeleteTransition(async () => {
      const formData = new FormData();
      formData.append('poId', poToDelete.id);
      const csrfToken = getCookie('csrf_token');
      if (csrfToken) {
          formData.append(CSRF_FORM_NAME, csrfToken);
      }
      const result = await deletePurchaseOrder(formData);
      if (result.success) {
        toast({ title: "Purchase Order Deleted", description: `PO #${poToDelete.po_number} has been removed.` });
        router.refresh();
      } else {
        toast({ variant: 'destructive', title: "Error Deleting PO", description: result.error });
      }
      setPoToDelete(null);
    });
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search by PO number or supplier..."
            onChange={(e) => handleSearch(e.target.value)}
            defaultValue={searchParams.get('query')?.toString()}
            className="pl-10"
          />
        </div>
        <Button asChild>
          <Link href="/purchase-orders/new">
            <Plus className="mr-2 h-4 w-4" />
            Create PO
          </Link>
        </Button>
      </div>

      <AlertDialog open={!!poToDelete} onOpenChange={(open) => !open && setPoToDelete(null)}>
        <AlertDialogContent>
            <AlertDialogHeader>
                <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
                <AlertDialogDescription>
                    This will permanently delete PO #{poToDelete?.po_number}. This action cannot be undone.
                </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
                <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
                <AlertDialogAction onClick={handleDelete} disabled={isDeleting} className="bg-destructive hover:bg-destructive/90">
                    {isDeleting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Yes, delete it
                </AlertDialogAction>
            </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {showEmptyState ? <EmptyPOState /> : (
        <Card>
          <CardContent className="p-0">
            <div className="max-h-[65vh] overflow-auto">
              <Table>
                <TableHeader className="sticky top-0 z-10 bg-background/80 backdrop-blur-sm">
                  <TableRow>
                    <TableHead>PO Number</TableHead>
                    <TableHead>Supplier</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Order Date</TableHead>
                    <TableHead>Expected Date</TableHead>
                    <TableHead className="text-right">Total Amount</TableHead>
                    <TableHead className="w-16 text-center">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {showNoResultsState ? (
                    <TableRow>
                      <TableCell colSpan={7} className="h-24 text-center">
                        No purchase orders found matching your search.
                      </TableCell>
                    </TableRow>
                  ) : initialPurchaseOrders.map(po => {
                    const today = new Date();
                    today.setHours(0, 0, 0, 0); // Compare against the start of today
                    const expectedDate = po.expected_date ? new Date(po.expected_date) : null;
                    const isOverdue = expectedDate && !['received', 'cancelled'].includes(po.status || '') && expectedDate < today;

                    return (
                    <TableRow key={po.id} className="hover:shadow-md transition-shadow cursor-pointer" onClick={() => router.push(`/purchase-orders/${po.id}`)}>
                      <TableCell className="font-medium">
                        <div className="flex items-center gap-2">
                            {isOverdue ? (
                                <TooltipProvider>
                                    <Tooltip>
                                        <TooltipTrigger>
                                            <div className="h-2.5 w-2.5 rounded-full bg-destructive" />
                                        </TooltipTrigger>
                                        <TooltipContent>
                                            <p>Overdue since {format(new Date(po.expected_date!), 'PP')}</p>
                                        </TooltipContent>
                                    </Tooltip>
                                </TooltipProvider>
                            ) : null}
                            {po.po_number}
                        </div>
                      </TableCell>
                      <TableCell>{po.supplier_name}</TableCell>
                      <TableCell>
                        <Badge variant={getStatusVariant(po.status)} className={getStatusColor(po.status)}>
                          {po.status ? po.status.charAt(0).toUpperCase() + po.status.slice(1) : 'Unknown'}
                        </Badge>
                      </TableCell>
                      <TableCell>{po.order_date ? format(new Date(po.order_date), 'MMM d, yyyy') : 'N/A'}</TableCell>
                      <TableCell>
                        {po.expected_date ? format(new Date(po.expected_date), 'MMM d, yyyy') : 'N/A'}
                      </TableCell>
                      <TableCell className="text-right">${po.total_amount.toLocaleString()}</TableCell>
                      <TableCell className="text-center">
                         <DropdownMenu>
                            <DropdownMenuTrigger asChild onClick={(e) => e.stopPropagation()}>
                                <Button variant="ghost" size="icon" className="h-8 w-8">
                                    <MoreHorizontal className="h-4 w-4" />
                                </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                                <DropdownMenuItem onSelect={() => router.push(`/purchase-orders/${po.id}`)}>View & Receive</DropdownMenuItem>
                                <DropdownMenuItem onSelect={() => router.push(`/purchase-orders/${po.id}/edit`)}><Edit className="mr-2 h-4 w-4" />Edit PO</DropdownMenuItem>
                                <DropdownMenuItem onSelect={(e) => {e.preventDefault(); setPoToDelete(po);}} className="text-destructive"><Trash2 className="mr-2 h-4 w-4"/>Delete PO</DropdownMenuItem>
                            </DropdownMenuContent>
                        </DropdownMenu>
                      </TableCell>
                    </TableRow>
                  )})}
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
