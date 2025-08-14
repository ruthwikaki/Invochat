
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { PurchaseOrdersClientPage } from "./purchase-orders-client-page";
import { getPurchaseOrders, getSuppliersData } from "@/app/data-actions";
import { Button } from "@/components/ui/button";
import Link from 'next/link';
import type { PurchaseOrderWithItemsAndSupplier, Supplier } from "@/types";

export const dynamic = 'force-dynamic';

export default async function PurchaseOrdersPage() {
    const [purchaseOrders, suppliers] = await Promise.all([
        getPurchaseOrders(),
        getSuppliersData()
    ]);

    return (
        <AppPage>
            <AppPageHeader
                title="Purchase Orders"
                description="Review and manage your purchase orders."
            >
                <Button asChild>
                    <Link href="/purchase-orders/new">Create Purchase Order</Link>
                </Button>
            </AppPageHeader>
            <div className="mt-6">
                <PurchaseOrdersClientPage 
                    initialPurchaseOrders={purchaseOrders as PurchaseOrderWithItemsAndSupplier[]}
                    suppliers={suppliers as Supplier[]}
                />
            </div>
        </AppPage>
    )
}
