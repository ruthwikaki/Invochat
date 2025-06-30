import { getPurchaseOrderById, getSuppliersData } from '@/app/data-actions';
import { PurchaseOrderForm } from '@/components/purchase-orders/po-form';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function EditPurchaseOrderPage({ params }: { params: { id: string } }) {
  const [purchaseOrder, suppliers] = await Promise.all([
    getPurchaseOrderById(params.id),
    getSuppliersData(),
  ]);

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
        title={`Edit Purchase Order #${purchaseOrder.po_number}`}
        description={`Modify the order details for the PO to ${purchaseOrder.supplier_name}.`}
      />
      <PurchaseOrderForm suppliers={suppliers} initialData={purchaseOrder} />
    </AppPage>
  );
}
