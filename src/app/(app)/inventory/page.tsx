
import { getUnifiedInventory, getInventoryCategories, getLocations, getSuppliersData, exportInventory, getInventoryAnalytics } from '@/app/data-actions';
import { InventoryClientPage } from '@/components/inventory/inventory-client-page';
import { Package } from 'lucide-react';
import { AppPage, AppPageHeader } from '@/components/ui/page';

const ITEMS_PER_PAGE = 50;

export default async function InventoryPage({
  searchParams,
}: {
  searchParams?: {
    query?: string;
    category?: string;
    location?: string;
    supplier?: string;
    page?: string;
  };
}) {
  const query = searchParams?.query || '';
  const category = searchParams?.category || '';
  const location = searchParams?.location || '';
  const supplier = searchParams?.supplier || '';
  const currentPage = parseInt(searchParams?.page || '1', 10);

  // Fetch data in parallel
  const [inventoryData, categories, locations, suppliers, analytics] = await Promise.all([
    getUnifiedInventory({ query, category, location, supplier, page: currentPage, limit: ITEMS_PER_PAGE }),
    getInventoryCategories(),
    getLocations(),
    getSuppliersData(),
    getInventoryAnalytics(),
  ]);

  const handleExport = async () => {
    'use server';
    return exportInventory({ query, category, location, supplier });
  }

  return (
    <AppPage className="flex flex-col h-full">
      <AppPageHeader
        title="Inventory Management"
        description="Search, filter, and view your entire inventory."
      />
      <InventoryClientPage 
        initialInventory={inventoryData.items} 
        totalCount={inventoryData.totalCount}
        itemsPerPage={ITEMS_PER_PAGE}
        categories={categories} 
        locations={locations}
        suppliers={suppliers}
        exportAction={handleExport}
        analyticsData={analytics}
      />
    </AppPage>
  );
}
