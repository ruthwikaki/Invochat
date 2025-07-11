
import { getInventoryRiskReport } from '@/app/data-actions';
import { InventoryRiskClientPage } from '@/components/reports/inventory-risk-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function InventoryRiskPage() {
  const data = await getInventoryRiskReport();

  return (
    <AppPage>
      <AppPageHeader
        title="Inventory Risk Report"
        description="Identify which products pose the most financial risk to your business."
      />
      <InventoryRiskClientPage initialData={data} />
    </AppPage>
  );
}
