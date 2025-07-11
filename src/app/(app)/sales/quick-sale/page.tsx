
import { QuickSaleForm } from "@/components/sales/quick-sale-form";
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { getLocations } from "@/app/data-actions";

export const dynamic = 'force-dynamic';

export default async function QuickSalePage() {
  const locations = await getLocations();

  return (
    <AppPage>
      <AppPageHeader
        title="Quick Sale"
        description="Record a new point-of-sale transaction."
      />
      <QuickSaleForm locations={locations} />
    </AppPage>
  )
}
