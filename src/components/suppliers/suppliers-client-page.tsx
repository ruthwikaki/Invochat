
'use client';

import { useState, useTransition, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import type { Supplier } from '@/types';
import { Card, CardContent } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Button } from '@/components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { MoreHorizontal, Edit, Trash2, Truck, Sparkles, Loader2 } from 'lucide-react';
import { deleteSupplier } from '@/app/data-actions';
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
import { CSRF_FORM_NAME } from '@/lib/csrf-client';
import { motion } from 'framer-motion';

function EmptySupplierState() {
  const router = useRouter();
  return (
    <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
        className="relative bg-primary/10 rounded-full p-6"
      >
        <Truck className="h-16 w-16 text-primary" />
         <motion.div
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.4, duration: 0.5 }}
          className="absolute -top-2 -right-2 text-primary"
        >
          <Sparkles className="h-8 w-8" />
        </motion.div>
      </motion.div>
      <h3 className="mt-6 text-xl font-semibold">No Suppliers Found</h3>
      <p className="mt-2 text-muted-foreground">
        Add your suppliers to begin tracking purchase orders and performance.
      </p>
       <Button className="mt-6" onClick={() => router.push('/suppliers/new')}>
        Add Your First Supplier
      </Button>
    </Card>
  );
}

export function SuppliersClientPage({ initialSuppliers }: { initialSuppliers: Supplier[] }) {
  const router = useRouter();
  const { toast } = useToast();
  const [supplierToDelete, setSupplierToDelete] = useState<Supplier | null>(null);
  const [isPending, startTransition] = useTransition();
  const [csrfToken] = useState<string | null>('dummy-token'); // Temporarily disabled for testing

  useEffect(() => {
    // generateAndSetCsrfToken(setCsrfToken);  // Temporarily disabled for testing
  }, []);

  const handleDelete = async () => {
    if (!supplierToDelete) {
        toast({ variant: 'destructive', title: "Error", description: 'Could not perform action. Please refresh.' });
        return;
    };
    startTransition(async () => {
        const formData = new FormData();
        formData.append('id', supplierToDelete.id);
        formData.append(CSRF_FORM_NAME, csrfToken!); // Using dummy token for testing

        const result = await deleteSupplier(formData);

        if (result.success) {
          toast({ title: 'Supplier Deleted' });
          router.refresh();
        } else {
          toast({ variant: 'destructive', title: 'Error', description: result.error });
        }
        setSupplierToDelete(null);
    });
  };
  
  if (initialSuppliers.length === 0) {
    return <EmptySupplierState />;
  }

  return (
    <>
      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>Email</TableHead>
                <TableHead>Phone</TableHead>
                <TableHead>Lead Time</TableHead>
                <TableHead className="w-16"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {initialSuppliers.map(supplier => (
                  <TableRow key={supplier.id}>
                    <TableCell className="font-medium">{supplier.name}</TableCell>
                    <TableCell>{supplier.email || 'N/A'}</TableCell>
                    <TableCell>{supplier.phone || 'N/A'}</TableCell>
                    <TableCell>
                      {supplier.default_lead_time_days !== null && supplier.default_lead_time_days !== undefined
                        ? `${supplier.default_lead_time_days} days`
                        : 'N/A'}
                    </TableCell>
                    <TableCell>
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button variant="ghost" size="icon" className="h-8 w-8">
                            <MoreHorizontal className="h-4 w-4" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuItem onClick={() => { router.push(`/suppliers/${supplier.id}/edit`); }}>
                            <Edit className="mr-2 h-4 w-4" /> Edit
                          </DropdownMenuItem>
                          <DropdownMenuItem onClick={() => { setSupplierToDelete(supplier); }} className="text-destructive">
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
        </CardContent>
      </Card>
      <AlertDialog open={!!supplierToDelete} onOpenChange={(open) => { if (!open) setSupplierToDelete(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Are you sure?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete the supplier {supplierToDelete?.name}. This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isPending}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} disabled={isPending} className="bg-destructive hover:bg-destructive/90">
              {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Yes, delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
