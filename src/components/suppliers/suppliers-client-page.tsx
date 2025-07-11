
'use client';

import type { Supplier } from '@/types';
import { useState, useMemo, useTransition } from 'react';
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useRouter } from 'next/navigation';
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
import { deleteSupplier } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import { Input } from '../ui/input';
import { Avatar, AvatarFallback } from '../ui/avatar';
import { Mail, Phone, Truck, MoreHorizontal, Edit, Trash2, Search, Loader2, Clock } from 'lucide-react';
import { motion } from 'framer-motion';
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf';

function SupplierCard({
  supplier,
  onEdit,
  onDelete,
}: {
  supplier: Supplier;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const [isAlertOpen, setAlertOpen] = useState(false);
  const [isDeleting, startDeleteTransition] = useTransition();
  const { toast } = useToast();

  const handleDelete = () => {
    startDeleteTransition(async () => {
      const formData = new FormData();
      formData.append('id', supplier.id);
      const csrfToken = getCookie('csrf_token');
      if (csrfToken) {
          formData.append(CSRF_FORM_NAME, csrfToken);
      }
      const result = await deleteSupplier(formData);
      if (result.success) {
        toast({ title: 'Supplier Deleted' });
        onDelete(); // Notify parent to update state
      } else {
        toast({ variant: 'destructive', title: 'Error', description: result.error });
      }
      setAlertOpen(false);
    });
  };

  return (
    <>
      <Card className="flex flex-col h-full hover:shadow-lg transition-shadow duration-300">
        <CardHeader className="flex flex-row items-start justify-between">
          <div className="flex items-center gap-4">
            <Avatar className="h-12 w-12">
              <AvatarFallback>{supplier.name.charAt(0)}</AvatarFallback>
            </Avatar>
            <div className="flex-1">
              <CardTitle>{supplier.name}</CardTitle>
              <CardDescription className="flex items-center gap-2 pt-1 text-muted-foreground">
                <Mail className="h-4 w-4" />
                {supplier.email || 'No email'}
              </CardDescription>
            </div>
          </div>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" className="h-8 w-8">
                <MoreHorizontal className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onClick={onEdit}>
                <Edit className="mr-2 h-4 w-4" /> Edit
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={() => setAlertOpen(true)} className="text-destructive">
                <Trash2 className="mr-2 h-4 w-4" /> Delete
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </CardHeader>
        <CardContent className="space-y-4 text-sm flex-grow">
          {supplier.phone && (
            <div className="flex items-center">
              <Phone className="h-4 w-4 mr-2 text-muted-foreground" />
              <span>{supplier.phone}</span>
            </div>
          )}
          {supplier.default_lead_time_days !== null && (
             <div className="flex items-center">
                <Clock className="h-4 w-4 mr-2 text-muted-foreground" />
                <span>Lead Time: {supplier.default_lead_time_days} days</span>
            </div>
          )}
        </CardContent>
      </Card>

      <AlertDialog open={isAlertOpen} onOpenChange={setAlertOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete {supplier.name}. This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
              disabled={isDeleting}
              className="bg-destructive hover:bg-destructive/90"
            >
              {isDeleting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Yes, delete it
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

export function SuppliersClientPage({ initialSuppliers }: { initialSuppliers: Supplier[] }) {
  const [suppliers, setSuppliers] = useState(initialSuppliers);
  const [searchTerm, setSearchTerm] = useState('');
  const router = useRouter();

  const filteredSuppliers = useMemo(() => {
    if (!searchTerm) return suppliers;
    return suppliers.filter(
      (supplier) =>
        supplier.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        (supplier.email && supplier.email.toLowerCase().includes(searchTerm.toLowerCase()))
    );
  }, [suppliers, searchTerm]);

  return (
    <div className="space-y-6">
      <div className="relative w-full max-w-sm">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input
          placeholder="Search by name or email..."
          className="pl-10"
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
        />
      </div>

      {suppliers.length === 0 ? (
           <Card className="h-60 flex flex-col items-center justify-center text-center border-2 border-dashed p-6">
              <motion.div
                initial={{ y: -20, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                transition={{ delay: 0.2, type: 'spring' }}
                className="bg-primary/10 rounded-full p-4"
              >
                <Truck className="h-12 w-12 text-primary" />
              </motion.div>
              <h3 className="mt-4 text-lg font-semibold">No Suppliers Found</h3>
              <p className="text-muted-foreground">
                Get started by adding your first supplier.
              </p>
            </Card>
      ) : (
        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          {filteredSuppliers.map((supplier) => (
            <SupplierCard
              key={supplier.id}
              supplier={supplier}
              onEdit={() => router.push(`/suppliers/${supplier.id}/edit`)}
              onDelete={() => setSuppliers((prev) => prev.filter((s) => s.id !== supplier.id))}
            />
          ))}
        </div>
      )}
    </div>
  );
}
