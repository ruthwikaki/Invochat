
import { getPurchaseOrderById } from '@/app/data-actions';
import { PurchaseOrderReceiveForm } from '@/components/purchase-orders/po-receive-form';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function PurchaseOrderDetailPage({ params }: { params: { id: string } }) {
  const purchaseOrder = await getPurchaseOrderById(params.id);

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
      />
      <PurchaseOrderReceiveForm purchaseOrder={purchaseOrder} />
    </AppPage>
  );
}
