
'use client';

import { useState, useTransition } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
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

interface PurchaseOrderClientPageProps {
  initialPurchaseOrders: PurchaseOrder[];
}

const getStatusVariant = (status: PurchaseOrder['status']) => {
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

export function PurchaseOrderClientPage({ initialPurchaseOrders }: PurchaseOrderClientPageProps) {
  const [purchaseOrders, setPurchaseOrders] = useState(initialPurchaseOrders);
  const [searchTerm, setSearchTerm] = useState('');
  const [isDeleting, startDeleteTransition] = useTransition();
  const [poToDelete, setPoToDelete] = useState<PurchaseOrder | null>(null);
  const router = useRouter();
  const { toast } = useToast();

  const filteredPOs = purchaseOrders.filter(po =>
    po.po_number.toLowerCase().includes(searchTerm.toLowerCase()) ||
    po.supplier_name?.toLowerCase().includes(searchTerm.toLowerCase())
  );
  
  const showEmptyState = filteredPOs.length === 0 && !searchTerm;

  const handleDelete = () => {
    if (!poToDelete) return;
    startDeleteTransition(async () => {
      const result = await deletePurchaseOrder(poToDelete.id);
      if (result.success) {
        toast({ title: "Purchase Order Deleted", description: `PO #${poToDelete.po_number} has been removed.` });
        setPurchaseOrders(prev => prev.filter(p => p.id !== poToDelete.id));
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
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
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
                  {filteredPOs.length === 0 && searchTerm ? (
                    <TableRow>
                      <TableCell colSpan={7} className="h-24 text-center">
                        No purchase orders found matching your search.
                      </TableCell>
                    </TableRow>
                  ) : filteredPOs.map(po => (
                    <TableRow key={po.id} className="hover:shadow-md transition-shadow cursor-pointer" onClick={() => router.push(`/purchase-orders/${po.id}`)}>
                      <TableCell className="font-medium">{po.po_number}</TableCell>
                      <TableCell>{po.supplier_name}</TableCell>
                      <TableCell>
                        <Badge variant={getStatusVariant(po.status)} className={getStatusColor(po.status)}>
                          {po.status.charAt(0).toUpperCase() + po.status.slice(1)}
                        </Badge>
                      </TableCell>
                      <TableCell>{format(new Date(po.order_date), 'MMM d, yyyy')}</TableCell>
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
                  ))}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
