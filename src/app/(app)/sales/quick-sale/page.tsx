
import { QuickSaleForm } from "@/components/sales/quick-sale-form";
import { AppPage, AppPageHeader } from "@/components/ui/page";

export const dynamic = 'force-dynamic';

export default async function QuickSalePage() {
  return (
    <AppPage>
      <AppPageHeader
        title="Quick Sale"
        description="Record a new point-of-sale transaction."
      />
      <QuickSaleForm />
    </AppPage>
  )
}
