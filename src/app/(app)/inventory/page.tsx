
import { getUnifiedInventory, getInventoryAnalytics, exportInventory } from '@/app/data-actions';
import { InventoryClientPage } from './inventory-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

const ITEMS_PER_PAGE = 25; 

export default async function InventoryPage({
  searchParams,
}: {
  searchParams: { [key: string]: string | string[] | undefined };
}) {
  const query = searchParams?.query?.toString() || '';
  const currentPage = parseInt(searchParams?.page?.toString() || '1', 10);
  const status = searchParams?.status?.toString() || 'all';
  const sortBy = searchParams?.sortBy?.toString() || 'product_title';
  const sortDirection = searchParams?.sortDirection?.toString() || 'asc';

  // Fetch data in parallel for better performance
  const [inventoryData, analytics] = await Promise.all([
    getUnifiedInventory({ query, page: currentPage, limit: ITEMS_PER_PAGE, status, sortBy, sortDirection }),
    getInventoryAnalytics(),
  ]);

  const handleExport = async (params: { query: string; status: string; sortBy: string; sortDirection: string; }) => {
    'use server';
    return exportInventory(params);
  }

  return (
    <AppPage>
        <AppPageHeader
            title="Inventory Management"
            description="Search, filter, and view your entire product catalog."
        />
        <div className="mt-6">
            <InventoryClientPage 
                initialInventory={inventoryData.items} 
                totalCount={inventoryData.totalCount}
                itemsPerPage={ITEMS_PER_PAGE}
                analyticsData={analytics}
                exportAction={handleExport}
            />
        </div>
    </AppPage>
  );
}
