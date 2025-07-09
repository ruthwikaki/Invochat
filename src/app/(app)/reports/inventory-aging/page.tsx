
import { getInventoryAgingData } from '@/app/data-actions';
import { InventoryAgingClientPage } from '@/components/reports/inventory-aging-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function InventoryAgingPage() {
  const data = await getInventoryAgingData();

  return (
    <AppPage>
      <AppPageHeader
        title="Inventory Aging Report"
        description="See how long your inventory has been sitting on the shelves."
      />
      <InventoryAgingClientPage initialData={data} />
    </AppPage>
  );
}

    