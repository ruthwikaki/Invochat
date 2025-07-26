
import { Suspense } from 'react';
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { PurchaseOrderForm } from "@/components/purchase-orders/purchase-order-form";
import { getSuppliersData, getProducts } from "@/app/data-actions";
import { Skeleton } from '@/components/ui/skeleton';

function PurchaseOrderFormSkeleton() {
    return (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2 space-y-6">
                <Skeleton className="h-64 w-full" />
            </div>
            <div className="lg:col-span-1 space-y-6">
                <Skeleton className="h-48 w-full" />
                <Skeleton className="h-24 w-full" />
            </div>
        </div>
    )
}

export default async function NewPurchaseOrderPage() {
    const suppliers = await getSuppliersData();
    const products = await getProducts();

    return (
        <AppPage>
            <AppPageHeader
                title="Create Purchase Order"
                description="Create a new purchase order to send to a supplier."
            />
            <div className="mt-6">
                <Suspense fallback={<PurchaseOrderFormSkeleton />}>
                    <PurchaseOrderForm suppliers={suppliers} products={products} />
                </Suspense>
            </div>
        </AppPage>
    )
}
