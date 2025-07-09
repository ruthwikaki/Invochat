

import { getPurchaseOrders, getPurchaseOrderAnalytics } from '@/app/data-actions';
import { PurchaseOrderClientPage } from '@/components/purchase-orders/po-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

const ITEMS_PER_PAGE = 25;

export default async function PurchaseOrdersPage({
    searchParams,
}: {
    searchParams?: {
        query?: string;
        page?: string;
    };
}) {
  const query = searchParams?.query || '';
  const currentPage = Number(searchParams?.page) || 1;
  const [poData, analyticsData] = await Promise.all([
    getPurchaseOrders({ query, page: currentPage }),
    getPurchaseOrderAnalytics(),
  ]);

  return (
    <AppPage className="flex flex-col h-full">
      <AppPageHeader
        title="Purchase Orders"
        description="Manage your incoming inventory and supplier orders."
      />
      <PurchaseOrderClientPage 
        initialPurchaseOrders={poData.items}
        totalCount={poData.totalCount}
        itemsPerPage={ITEMS_PER_PAGE}
        analyticsData={analyticsData}
      />
    </AppPage>
  );
}
```
