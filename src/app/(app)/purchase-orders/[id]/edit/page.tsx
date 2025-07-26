
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { PurchaseOrderForm } from "@/components/purchase-orders/purchase-order-form";
import { getPurchaseOrderById, getSuppliersData, getProducts } from "@/app/data-actions";
import { notFound } from "next/navigation";

export default async function EditPurchaseOrderPage({ params }: { params: { id: string } }) {
    const purchaseOrder = await getPurchaseOrderById(params.id);
    if (!purchaseOrder) {
        notFound();
    }
    
    const suppliers = await getSuppliersData();
    const products = await getProducts();

    return (
        <AppPage>
            <AppPageHeader
                title={`Edit PO #${purchaseOrder.po_number}`}
                description="Update the details for this purchase order."
            />
            <div className="mt-6">
                <PurchaseOrderForm 
                    initialData={purchaseOrder}
                    suppliers={suppliers} 
                    products={products} 
                />
            </div>
        </AppPage>
    )
}
