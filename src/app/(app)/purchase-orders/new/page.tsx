import { getSuppliersData } from '@/app/data-actions';
import { PurchaseOrderCreateForm } from '@/components/purchase-orders/po-create-form';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function CreatePurchaseOrderPage() {
  const suppliers = await getSuppliersData();

  return (
    <AppPage className="flex flex-col h-full">
      <AppPageHeader
        title="New Purchase Order"
        description="Create a new order to send to your suppliers."
      />
      <PurchaseOrderCreateForm suppliers={suppliers} />
    </AppPage>
  );
}
