
import { getUnifiedInventory, getInventoryCategories, getLocations } from '@/app/data-actions';
import { InventoryClientPage } from '@/components/inventory/inventory-client-page';
import { Package } from 'lucide-react';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function InventoryPage({
  searchParams,
}: {
  searchParams?: {
    query?: string;
    category?: string;
    location?: string;
  };
}) {
  const query = searchParams?.query || '';
  const category = searchParams?.category || '';
  const location = searchParams?.location || '';

  // Fetch data in parallel
  const [inventory, categories, locations] = await Promise.all([
    getUnifiedInventory({ query, category, location }),
    getInventoryCategories(),
    getLocations()
  ]);

  return (
    <AppPage className="flex flex-col h-full">
      <AppPageHeader
        title="Inventory Management"
        description="Search, filter, and view your entire inventory."
      />
      <InventoryClientPage initialInventory={inventory} categories={categories} locations={locations} />
    </AppPage>
  );
}
