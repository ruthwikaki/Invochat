
'use client';

import { getPurchaseOrderById, deletePurchaseOrder, emailPurchaseOrder } from '@/app/data-actions';
import { PurchaseOrderReceiveForm } from '@/components/purchase-orders/po-receive-form';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Button } from '@/components/ui/button';
import { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem } from '@/components/ui/dropdown-menu';
import { useToast } from '@/hooks/use-toast';
import { Edit, Trash2, Mail, MoreVertical, Loader2 } from 'lucide-react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, useTransition, useEffect } from 'react';
import type { PurchaseOrder } from '@/types';
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
import { Skeleton } from '@/components/ui/skeleton';

async function fetchPO(id: string): Promise<PurchaseOrder | null> {
    return getPurchaseOrderById(id);
}

function LoadingState() {
    return (
        <AppPage>
            <AppPageHeader title="Loading Purchase Order...">
                <div className="flex gap-2">
                    <Skeleton className="h-10 w-24" />
                    <Skeleton className="h-10 w-10" />
                </div>
            </AppPageHeader>
            <div className="space-y-6">
                <Skeleton className="h-48 w-full" />
                <Skeleton className="h-96 w-full" />
            </div>
        </AppPage>
    )
}

export default function PurchaseOrderDetailPage({ params }: { params: { id: string } }) {
  const router = useRouter();
  const { toast } = useToast();
  const [isDeleting, startDeleteTransition] = useTransition();
  const [isEmailing, startEmailTransition] = useTransition();
  const [isAlertOpen, setAlertOpen] = useState(false);
  
  const [purchaseOrder, setPurchaseOrder] = useState<PurchaseOrder | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchPO(params.id).then(data => {
        setPurchaseOrder(data);
        setLoading(false);
    });
  }, [params.id]);


  const handleDelete = () => {
    if (!purchaseOrder) return;
    startDeleteTransition(async () => {
      const result = await deletePurchaseOrder(purchaseOrder.id);
      if (result.success) {
        toast({ title: "Purchase Order Deleted", description: `PO #${purchaseOrder.po_number} has been removed.` });
        router.push('/purchase-orders');
      } else {
        toast({ variant: 'destructive', title: "Error Deleting PO", description: result.error });
        setAlertOpen(false);
      }
    });
  };
  
  const handleEmail = () => {
    if (!purchaseOrder) return;
    startEmailTransition(async () => {
      const result = await emailPurchaseOrder(purchaseOrder.id);
       if (result.success) {
        toast({ title: "Email Sent (Simulated)", description: `PO #${purchaseOrder.po_number} was emailed to ${purchaseOrder.supplier_name}.` });
      } else {
        toast({ variant: 'destructive', title: "Error Emailing PO", description: result.error });
      }
    })
  }

  if (loading) {
    return <LoadingState />;
  }

  if (!purchaseOrder) {
    return (
        <AppPage>
            <AppPageHeader title="Purchase Order Not Found" />
            <p>The requested purchase order could not be found.</p>
        </AppPage>
    )
  }

  return (
    <AppPage className="flex flex-col h-full">
      <AppPageHeader
        title={`Purchase Order #${purchaseOrder.po_number}`}
        description={`Manage and receive items for the order from ${purchaseOrder.supplier_name}.`}
      >
        <div className="flex items-center gap-2">
            <Button variant="outline" asChild>
                <Link href={`/purchase-orders/${purchaseOrder.id}/edit`}>
                    <Edit className="mr-2 h-4 w-4" /> Edit
                </Link>
            </Button>
             <DropdownMenu>
                <DropdownMenuTrigger asChild>
                    <Button variant="ghost" size="icon">
                        <MoreVertical className="h-4 w-4" />
                    </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                    <DropdownMenuItem onSelect={handleEmail} disabled={isEmailing}>
                        {isEmailing ? <Loader2 className="mr-2 h-4 w-4 animate-spin"/> : <Mail className="mr-2 h-4 w-4" />}
                        Email to Supplier
                    </DropdownMenuItem>
                    <DropdownMenuItem onSelect={() => setAlertOpen(true)} className="text-destructive">
                        <Trash2 className="mr-2 h-4 w-4" />
                        Delete PO
                    </DropdownMenuItem>
                </DropdownMenuContent>
            </DropdownMenu>
        </div>
      </AppPageHeader>
      <PurchaseOrderReceiveForm purchaseOrder={purchaseOrder} />

      <AlertDialog open={isAlertOpen} onOpenChange={setAlertOpen}>
        <AlertDialogContent>
            <AlertDialogHeader>
                <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
                <AlertDialogDescription>
                    This action cannot be undone. This will permanently delete PO #{purchaseOrder.po_number}.
                </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
                <AlertDialogCancel>Cancel</AlertDialogCancel>
                <AlertDialogAction onClick={handleDelete} disabled={isDeleting} className="bg-destructive hover:bg-destructive/90">
                    {isDeleting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Yes, delete it
                </AlertDialogAction>
            </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

    </AppPage>
  );
}
