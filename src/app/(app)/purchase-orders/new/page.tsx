
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { PurchaseOrderForm } from "@/components/purchase-orders/purchase-order-form";
import { getSuppliersData, getProducts } from "@/app/data-actions";

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
                <PurchaseOrderForm suppliers={suppliers} products={products} />
            </div>
        </AppPage>
    )
}
