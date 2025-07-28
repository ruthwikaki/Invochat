
'use client';

import { useState, useTransition, Fragment, useEffect } from 'react';
import type { PurchaseOrderWithItemsAndSupplier, Supplier } from '@/types';
import { Card, CardContent } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { formatCentsAsCurrency } from '@/lib/utils';
import { cn } from '@/lib/utils';
import { motion } from 'framer-motion';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { MoreHorizontal, Edit, Trash2, FileText, Loader2, ChevronDown } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useRouter } from 'next/navigation';
import { deletePurchaseOrder } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { CSRF_FORM_NAME, generateAndSetCsrfToken } from '@/lib/csrf-client';

interface PurchaseOrdersClientPageProps {
  initialPurchaseOrders: PurchaseOrderWithItemsAndSupplier[];
  suppliers: Supplier[];
}

const statusColors: { [key: string]: string } = {
    'Draft': 'bg-gray-500/10 text-gray-600 dark:text-gray-400 border-gray-500/20',
    'Ordered': 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/20',
    'Partially Received': 'bg-amber-500/10 text-amber-600 dark:text-amber-400 border-amber-500/20',
    'Received': 'bg-green-500/10 text-green-600 dark:text-green-400 border-green-500/20',
    'Cancelled': 'bg-red-500/10 text-red-600 dark:text-red-400 border-red-500/20',
};

function EmptyPurchaseOrderState() {
  const router = useRouter();
  return (
    <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
        className="relative bg-primary/10 rounded-full p-6"
      >
        <FileText className="h-16 w-16 text-primary" />
      </motion.div>
      <h3 className="mt-6 text-xl font-semibold">No Purchase Orders Found</h3>
      <p className="mt-2 text-muted-foreground">
        Create your first purchase order to start tracking incoming inventory.
      </p>
      <Button className="mt-4" onClick={() => router.push('/purchase-orders/new')}>
        Create Purchase Order
      </Button>
    </Card>
  );
}

export function PurchaseOrdersClientPage({ initialPurchaseOrders, suppliers }: PurchaseOrdersClientPageProps) {
  const router = useRouter();
  const { toast } = useToast();
  const [isDeleting, startDeleteTransition] = useTransition();
  const [poToDelete, setPoToDelete] = useState<PurchaseOrderWithItemsAndSupplier | null>(null);
  const [expandedPoId, setExpandedPoId] = useState<string | null>(null);
  const [csrfToken, setCsrfToken] = useState<string | null>(null);

  useEffect(() => {
    generateAndSetCsrfToken(setCsrfToken);
  }, []);

  const toggleExpand = (poId: string) => {
    setExpandedPoId(prevId => (prevId === poId ? null : poId));
  };

  const handleDelete = () => {
    if (!poToDelete || !csrfToken) {
        toast({ variant: 'destructive', title: "Error", description: 'Could not perform action. Please refresh.' });
        return;
    };

    startDeleteTransition(async () => {
        const formData = new FormData();
        formData.append(CSRF_FORM_NAME, csrfToken);
        formData.append('id', poToDelete.id);
        const result = await deletePurchaseOrder(formData);

        if (result.success) {
            toast({ title: "Purchase Order Deleted" });
            router.refresh();
        } else {
            toast({ variant: 'destructive', title: "Error", description: result.error });
        }
        setPoToDelete(null);
    });
  }

  if (initialPurchaseOrders.length === 0) {
    return <EmptyPurchaseOrderState />;
  }

  return (
    <>
    <Card>
      <CardContent className="p-0">
        <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-[50px]"></TableHead>
              <TableHead>PO Number</TableHead>
              <TableHead>Supplier</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Created Date</TableHead>
              <TableHead>Expected Arrival</TableHead>
              <TableHead className="text-right">Total Cost</TableHead>
              <TableHead className="w-16"></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {initialPurchaseOrders.map(po => (
                <Fragment key={po.id}>
                    <TableRow onClick={() => toggleExpand(po.id)} className="cursor-pointer">
                      <TableCell>
                        <ChevronDown className={cn('h-5 w-5 text-muted-foreground transition-transform', expandedPoId === po.id && 'rotate-180')} />
                      </TableCell>
                      <TableCell className="font-medium">{po.po_number}</TableCell>
                      <TableCell>{po.supplier_name || 'N/A'}</TableCell>
                      <TableCell>
                        <Badge variant="outline" className={cn("whitespace-nowrap", statusColors[po.status] || '')}>
                            {po.status}
                        </Badge>
                      </TableCell>
                      <TableCell>{format(new Date(po.created_at), 'MMM d, yyyy')}</TableCell>
                      <TableCell>{po.expected_arrival_date ? format(new Date(po.expected_arrival_date), 'MMM d, yyyy') : 'N/A'}</TableCell>
                      <TableCell className="text-right font-tabular">{formatCentsAsCurrency(po.total_cost)}</TableCell>
                      <TableCell>
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button variant="ghost" size="icon" className="h-8 w-8" onClick={(e) => e.stopPropagation()}>
                                <MoreHorizontal className="h-4 w-4" />
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                              <DropdownMenuItem onClick={() => router.push(`/purchase-orders/${po.id}/edit`)}>
                                <Edit className="mr-2 h-4 w-4" /> Edit
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => setPoToDelete(po)} className="text-destructive">
                                <Trash2 className="mr-2 h-4 w-4" /> Delete
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                      </TableCell>
                    </TableRow>
                    {expandedPoId === po.id && (
                        <TableRow className="bg-muted/50">
                            <TableCell colSpan={8} className="p-4">
                                <div className="p-2 bg-background rounded-md border">
                                    <h4 className="font-semibold px-2 py-1">Line Items</h4>
                                    <Table>
                                        <TableHeader>
                                            <TableRow>
                                                <TableHead>Product SKU</TableHead>
                                                <TableHead>Description</TableHead>
                                                <TableHead className="text-right">Quantity</TableHead>
                                                <TableHead className="text-right">Unit Cost</TableHead>
                                                <TableHead className="text-right">Line Total</TableHead>
                                            </TableRow>
                                        </TableHeader>
                                        <TableBody>
                                            {po.line_items.map(item => (
                                                <TableRow key={item.id}>
                                                    <TableCell className="font-mono text-xs">{item.sku}</TableCell>
                                                    <TableCell>{item.product_name}</TableCell>
                                                    <TableCell className="text-right">{item.quantity}</TableCell>
                                                    <TableCell className="text-right">{formatCentsAsCurrency(item.cost)}</TableCell>
                                                    <TableCell className="text-right font-semibold">{formatCentsAsCurrency(item.quantity * item.cost)}</TableCell>
                                                </TableRow>
                                            ))}
                                        </TableBody>
                                    </Table>
                                </div>
                            </TableCell>
                        </TableRow>
                    )}
                </Fragment>
              ))
            }
          </TableBody>
        </Table>
        </div>
      </CardContent>
    </Card>

     <AlertDialog open={!!poToDelete} onOpenChange={(open) => { if (!open) setPoToDelete(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Are you sure?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete Purchase Order {poToDelete?.po_number}. This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} disabled={isDeleting || !csrfToken} className="bg-destructive hover:bg-destructive/90">
              {isDeleting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : 'Yes, delete'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

    