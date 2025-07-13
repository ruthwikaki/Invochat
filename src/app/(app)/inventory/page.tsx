

import { getUnifiedInventory, getInventoryCategories, getSuppliersData, exportInventory, getInventoryAnalytics } from '@/app/data-actions';
import { InventoryClientPage } from '@/components/inventory/inventory-client-page';
import { Package } from 'lucide-react';
import { AppPage, AppPageHeader } from '@/components/ui/page';

const ITEMS_PER_PAGE = 50; // Use a higher limit now that we group by product

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
  const [inventoryData, categories, suppliers, analytics] = await Promise.all([
    getUnifiedInventory({ query, page: currentPage, limit: ITEMS_PER_PAGE }),
    getInventoryCategories(),
    getSuppliersData(),
    getInventoryAnalytics(),
  ]);

  const handleExport = async () => {
    'use server';
    return exportInventory({ query });
  }

  return (
    <AppPage className="flex flex-col h-full">
      <AppPageHeader
        title="Inventory Management"
        description="Search, filter, and view your entire product catalog."
      />
      <InventoryClientPage 
        initialInventory={inventoryData.items} 
        totalCount={inventoryData.totalCount}
        itemsPerPage={ITEMS_PER_PAGE}
        categories={categories} 
        suppliers={suppliers}
        exportAction={handleExport}
        analyticsData={analytics}
      />
    </AppPage>
  );
}
