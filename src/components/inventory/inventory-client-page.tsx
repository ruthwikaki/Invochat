'use client';

import { useState } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { useDebouncedCallback } from 'use-debounce';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { DataTable } from '@/components/ai-response/data-table';
import type { UnifiedInventoryItem } from '@/types';
import { Card, CardContent } from '@/components/ui/card';
import { Search } from 'lucide-react';

interface InventoryClientPageProps {
  initialInventory: UnifiedInventoryItem[];
  categories: string[];
}

function formatInventoryData(inventory: UnifiedInventoryItem[]) {
    return inventory.map(item => ({
        SKU: item.sku,
        'Product Name': item.product_name,
        Category: item.category || 'N/A',
        Quantity: item.quantity,
        'Unit Cost': `$${item.cost.toFixed(2)}`,
        'Total Value': `$${item.total_value.toFixed(2)}`,
    }));
}


export function InventoryClientPage({ initialInventory, categories }: InventoryClientPageProps) {
  const [inventory, setInventory] = useState(initialInventory);
  const searchParams = useSearchParams();
  const pathname = usePathname();
  const { replace } = useRouter();

  const handleSearch = useDebouncedCallback((term: string) => {
    const params = new URLSearchParams(searchParams);
    if (term) {
      params.set('query', term);
    } else {
      params.delete('query');
    }
    replace(`${pathname}?${params.toString()}`);
  }, 300);

  const handleCategoryChange = (category: string) => {
    const params = new URLSearchParams(searchParams);
    if (category && category !== 'all') {
      params.set('category', category);
    } else {
      params.delete('category');
    }
    replace(`${pathname}?${params.toString()}`);
  };

  const formattedData = formatInventoryData(inventory);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-4">
        <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
                placeholder="Search by product name or SKU..."
                onChange={(e) => handleSearch(e.target.value)}
                defaultValue={searchParams.get('query')?.toString()}
                className="pl-10"
            />
        </div>
        <Select
            onValueChange={handleCategoryChange}
            defaultValue={searchParams.get('category') || 'all'}
        >
          <SelectTrigger className="w-full md:w-[240px]">
            <SelectValue placeholder="Filter by category" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Categories</SelectItem>
            {categories.map((category) => (
              <SelectItem key={category} value={category}>
                {category}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <Card>
        <CardContent className="p-0">
            {formattedData.length > 0 ? (
                <DataTable data={formattedData} />
            ) : (
                <div className="text-center p-8 text-muted-foreground">
                    <p>No inventory found matching your criteria.</p>
                </div>
            )}
        </CardContent>
      </Card>
    </div>
  );
}
