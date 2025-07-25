

import { getUnifiedInventory, getInventoryAnalytics, exportInventory } from '@/app/data-actions';
import { InventoryClientPage } from './inventory-client-page';
import { AppPageHeader } from '@/components/ui/page';

const ITEMS_PER_PAGE = 25; 

export default async function InventoryPage({
  searchParams,
}: {
  searchParams?: {
    query?: string;
    page?: string;
    status?: string;
    sortBy?: string;
    sortDirection?: string;
  };
}) {
  const query = searchParams?.query || '';
  const currentPage = parseInt(searchParams?.page || '1', 10);
  const status = searchParams?.status || 'all';
  const sortBy = searchParams?.sortBy || 'product_title';
  const sortDirection = searchParams?.sortDirection || 'asc';

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
    <>
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
    </>
  );
}
