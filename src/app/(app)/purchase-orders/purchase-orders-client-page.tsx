
'use client';

import { useState, useTransition } from 'react';
import type { PurchaseOrderWithSupplier, Supplier } from '@/types';
import { Card, CardContent } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { formatCentsAsCurrency } from '@/lib/utils';
import { cn } from '@/lib/utils';
import { motion } from 'framer-motion';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { MoreHorizontal, Edit, Trash2, FileText, Loader2 } from 'lucide-react';
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
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf-client';

interface PurchaseOrdersClientPageProps {
  initialPurchaseOrders: PurchaseOrderWithSupplier[];
  suppliers: Supplier[];
}

const statusColors: { [key: string]: string } = {
    'Draft': 'bg-gray-500/10 text-gray-600 dark:text-gray-400 border-gray-500/20',
    'Ordered': 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/20',
    'Partially Received': 'bg-amber-500/10 text-amber-600 dark:text-amber-400 border-amber-500/20',
    'Received': 'bg-green-500/10 text-green-600 dark:text-green-400 border-green-500/20',
    'Cancelled': 'bg-red-500/10 text-red-600 dark:text-red-400 border-red-500/20',
};

export function PurchaseOrdersClientPage({ initialPurchaseOrders, suppliers }: PurchaseOrdersClientPageProps) {
  const router = useRouter();
  const { toast } = useToast();
  const [isDeleting, startDeleteTransition] = useTransition();
  const [poToDelete, setPoToDelete] = useState<PurchaseOrderWithSupplier | null>(null);

  const handleDelete = () => {
    if (!poToDelete) return;

    startDeleteTransition(async () => {
        const formData = new FormData();
        const csrfToken = getCookie(CSRF_FORM_NAME);
        if (csrfToken) {
            formData.append(CSRF_FORM_NAME, csrfToken);
        }
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

  return (
    <>
    <Card>
      <CardContent className="p-0">
        <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
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
                <TableRow key={po.id}>
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
                          <Button variant="ghost" size="icon" className="h-8 w-8">
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
              ))
            }
          </TableBody>
        </Table>
        </div>
      </CardContent>
    </Card>

     <AlertDialog open={!!poToDelete} onOpenChange={setPoToDelete}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Are you sure?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete Purchase Order {poToDelete?.po_number}. This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} disabled={isDeleting} className="bg-destructive hover:bg-destructive/90">
              {isDeleting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : 'Yes, delete'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
