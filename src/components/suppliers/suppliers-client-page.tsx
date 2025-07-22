
'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import type { Supplier } from '@/types';
import { Card, CardContent } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Button } from '@/components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { MoreHorizontal, Edit, Trash2 } from 'lucide-react';
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
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf-client';
import { db } from '@/lib/database-queries';
import { getCurrentCompanyId } from '@/lib/auth-helpers';
import { Skeleton } from '../ui/skeleton';


export function SuppliersClientPage({ initialSuppliers }: { initialSuppliers: Supplier[] }) {
  const router = useRouter();
  const { toast } = useToast();
  const [supplierToDelete, setSupplierToDelete] = useState<Supplier | null>(null);
  const [suppliers, setSuppliers] = useState(initialSuppliers);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    async function fetchData() {
      try {
        setLoading(true);
        const companyId = await getCurrentCompanyId();
        if (!companyId) return;
        
        const data = await db.getCompanySuppliers(companyId);
        setSuppliers(data as Supplier[]);
      } catch (error) {
        console.error('Data fetch failed:', error);
      } finally {
        setLoading(false);
      }
    }
    
    fetchData();
  }, []);

  const handleDelete = async () => {
    if (!supplierToDelete) return;
    const formData = new FormData();
    formData.append('id', supplierToDelete.id);
    const csrfToken = getCookie(CSRF_FORM_NAME);
    if(csrfToken) formData.append(CSRF_FORM_NAME, csrfToken);

    const result = await deleteSupplier(formData);

    if (result.success) {
      toast({ title: 'Supplier Deleted' });
      setSuppliers(prev => prev.filter(s => s.id !== supplierToDelete.id));
    } else {
      toast({ variant: 'destructive', title: 'Error', description: result.error });
    }
    setSupplierToDelete(null);
  };
  
  if (loading) {
      return (
          <div className="space-y-2">
            {Array.from({ length: 5 }).map((_, i) => (
              <Skeleton key={i} className="h-12 w-full" />
            ))}
          </div>
      )
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
              {suppliers.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={5} className="h-24 text-center">
                    No suppliers found.
                  </TableCell>
                </TableRow>
              ) : (
                suppliers.map(supplier => (
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
              )}
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
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} className="bg-destructive hover:bg-destructive/90">
              Yes, delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

    