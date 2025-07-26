
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { PurchaseOrdersClientPage } from "./purchase-orders-client-page";
import { getPurchaseOrders, getSuppliersData } from "@/app/data-actions";
import { Button } from "@/components/ui/button";
import Link from 'next/link';

export const dynamic = 'force-dynamic';

export default async function PurchaseOrdersPage() {
    const purchaseOrders = await getPurchaseOrders();
    const suppliers = await getSuppliersData();

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
                    initialPurchaseOrders={purchaseOrders} 
                    suppliers={suppliers}
                />
            </div>
        </AppPage>
    )
}
