
import { getPurchaseOrders } from '@/app/data-actions';
import { PurchaseOrderClientPage } from '@/components/purchase-orders/po-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function PurchaseOrdersPage() {
  const purchaseOrders = await getPurchaseOrders();

  return (
    <AppPage className="flex flex-col h-full">
      <AppPageHeader
        title="Purchase Orders"
        description="Manage your incoming inventory and supplier orders."
      />
      <PurchaseOrderClientPage initialPurchaseOrders={purchaseOrders} />
    </AppPage>
  );
}
