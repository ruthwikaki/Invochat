
import { getPurchaseOrders } from '@/app/data-actions';
import { PurchaseOrderClientPage } from './po-client-page';
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

  const { items, totalCount } = await getPurchaseOrders({ query, page: currentPage, limit: ITEMS_PER_PAGE });

  return (
    <AppPage>
      <AppPageHeader 
        title="Purchase Orders"
        description="Create, manage, and track your incoming inventory."
      />
      <PurchaseOrderClientPage 
        initialPurchaseOrders={items}
        totalCount={totalCount}
        itemsPerPage={ITEMS_PER_PAGE}
      />
    </AppPage>
  );
}
