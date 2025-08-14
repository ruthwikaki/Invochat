
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { PurchaseOrdersClientPage } from "./purchase-orders-client-page";
import { getPurchaseOrdersFromDB, getSuppliersDataFromDB } from "@/services/database";
import { Button } from "@/components/ui/button";
import Link from 'next/link';
import { getAuthContext } from "@/lib/auth-helpers";
import type { PurchaseOrderWithItemsAndSupplier, Supplier } from "@/types";

export const dynamic = 'force-dynamic';

export default async function PurchaseOrdersPage() {
    const { companyId } = await getAuthContext();
    const [purchaseOrders, suppliers] = await Promise.all([
        getPurchaseOrdersFromDB(companyId),
        getSuppliersDataFromDB(companyId)
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
                    suppliers={suppliers}
                />
            </div>
        </AppPage>
    )
}
