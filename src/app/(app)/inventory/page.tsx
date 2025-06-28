import { SidebarTrigger } from '@/components/ui/sidebar';
import { getUnifiedInventory, getInventoryCategories } from '@/services/database';
import { InventoryClientPage } from '@/components/inventory/inventory-client-page';
import { Package } from 'lucide-react';

export default async function InventoryPage({
  searchParams,
}: {
  searchParams?: {
    query?: string;
    category?: string;
  };
}) {
  const query = searchParams?.query || '';
  const category = searchParams?.category || '';

  // Fetch data in parallel
  const [inventory, categories] = await Promise.all([
    getUnifiedInventory({ query, category }),
    getInventoryCategories()
  ]);

  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6 flex flex-col h-full">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <div>
            <h1 className="text-2xl font-semibold flex items-center gap-2">
              <Package className="h-6 w-6" />
              Inventory Management
            </h1>
            <p className="text-muted-foreground text-sm">
              Search, filter, and view your entire inventory.
            </p>
          </div>
        </div>
      </div>
      <InventoryClientPage initialInventory={inventory} categories={categories} />
    </div>
  );
}
