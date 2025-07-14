
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { PurchaseOrdersClientPage } from "./purchase-orders-client-page";
import { getPurchaseOrders } from "@/app/data-actions";


export default async function PurchaseOrdersPage() {
    const purchaseOrders = await getPurchaseOrders();

    return (
        <div className="space-y-6">
            <AppPageHeader 
                title="Purchase Orders"
                description="Review and manage your purchase orders."
            />
            <PurchaseOrdersClientPage initialPurchaseOrders={purchaseOrders} />
        </div>
    )
}
