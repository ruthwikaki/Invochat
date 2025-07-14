
import { getUnifiedInventory, getInventoryAnalytics, exportInventory } from '@/app/data-actions';
import { InventoryClientPage } from './inventory-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

const ITEMS_PER_PAGE = 25; 

export default async function InventoryPage({
  searchParams,
}: {
  searchParams?: {
    query?: string;
    page?: string;
  };
}) {
  const query = searchParams?.query || '';
  const currentPage = parseInt(searchParams?.page || '1', 10);

  // Fetch data in parallel
  const [inventoryData, analytics] = await Promise.all([
    getUnifiedInventory({ query, page: currentPage, limit: ITEMS_PER_PAGE }),
    getInventoryAnalytics(),
  ]);

  const handleExport = async () => {
    'use server';
    return exportInventory({ query });
  }

  return (
    <div className="space-y-6">
      <AppPageHeader
        title="Inventory Management"
        description="Search, filter, and view your entire product catalog."
      />
      <InventoryClientPage 
        initialInventory={inventoryData.items} 
        totalCount={inventoryData.totalCount}
        itemsPerPage={ITEMS_PER_PAGE}
        analyticsData={analytics}
        exportAction={handleExport}
      />
    </div>
  );
}
