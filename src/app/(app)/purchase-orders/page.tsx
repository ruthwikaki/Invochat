
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { PurchaseOrdersClientPage } from "./purchase-orders-client-page";
import { getPurchaseOrders } from "@/app/data-actions";

export const dynamic = 'force-dynamic';

export default async function PurchaseOrdersPage() {
    const purchaseOrders = await getPurchaseOrders();

    return (
        <AppPage>
            <AppPageHeader
                title="Purchase Orders"
                description="Review and manage your purchase orders."
            />
            <div className="mt-6">
                <PurchaseOrdersClientPage initialPurchaseOrders={purchaseOrders} />
            </div>
        </AppPage>
    )
}
