
'use client';

import { useState, useMemo, Fragment } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { useDebouncedCallback } from 'use-debounce';
import Link from 'next/link';
import { Input } from '@/components/ui/input';
import type { UnifiedInventoryItem, InventoryAnalytics } from '@/types';
import { Card, CardContent } from '@/components/ui/card';
import { Search, ChevronDown, Package as PackageIcon, AlertTriangle, DollarSign, History, ArrowDownUp } from 'lucide-react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { motion } from 'framer-motion';
import { cn } from '@/lib/utils';
import { Package, Sparkles } from 'lucide-react';
import { ExportButton } from '@/components/ui/export-button';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { formatCentsAsCurrency } from '@/lib/utils';
import { InventoryHistoryDialog } from '@/components/inventory/inventory-history-dialog';
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from '@/components/ui/select';

interface InventoryClientPageProps {
  initialInventory: UnifiedInventoryItem[];
  totalCount: number;
  itemsPerPage: number;
  analyticsData: InventoryAnalytics;
  exportAction: (params: { query: string; status: string; sortBy: string; sortDirection: string; }) => Promise<{ success: boolean; data?: string; error?: string }>;
}

type SortableColumn = 'product_title' | 'product_status' | 'inventory_quantity';

const AnalyticsCard = ({ title, value, icon: Icon, label }: { title: string, value: string | number, icon: React.ElementType, label?: string }) => (
    <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
            <Icon className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
            <div className="text-2xl font-bold font-tabular">{typeof value === 'number' && !Number.isInteger(value) ? formatCentsAsCurrency(value) : value.toLocaleString()}</div>
            {label && <p className="text-xs text-muted-foreground">{label}</p>}
        </CardContent>
    </Card>
);

const PaginationControls = ({ totalCount, itemsPerPage }: { totalCount: number, itemsPerPage: number }) => {
    const router = useRouter();
    const pathname = usePathname();
    const searchParams = useSearchParams();
    const currentPage = Number(searchParams.get('page')) || 1;
    const totalPages = Math.ceil(totalCount / itemsPerPage);

    const createPageURL = (pageNumber: number | string) => {
        const params = new URLSearchParams(searchParams);
        params.set('page', pageNumber.toString());
        return `${pathname}?${params.toString()}`;
    };

    if (totalPages <= 1) {
        return null;
    }

    return (
        <div className="flex items-center justify-between p-4 border-t">
            <p className="text-sm text-muted-foreground">
                Showing page <strong>{currentPage}</strong> of <strong>{totalPages}</strong> ({totalCount} items)
            </p>
            <div className="flex items-center gap-2">
                <Button
                    variant="outline"
                    onClick={() => { router.push(createPageURL(currentPage - 1)); }}
                    disabled={currentPage <= 1}
                >
                    Previous
                </Button>
                <Button
                    variant="outline"
                    onClick={() => { router.push(createPageURL(currentPage + 1)); }}
                    disabled={currentPage >= totalPages}
                >
                    Next
                </Button>
            </div>
        </div>
    );
};


const StatusBadge = ({ quantity }: { quantity: number }) => {
    if (quantity <= 0) {
        return <Badge variant="destructive" className="bg-destructive/10 text-destructive border-destructive/20">Out of Stock</Badge>;
    }
    if (quantity < 10) { // A generic low stock indicator
        return <Badge variant="secondary" className="bg-warning/10 text-amber-600 dark:text-amber-400 border-warning/20">Low Stock</Badge>;
    }
    return <Badge variant="secondary" className="bg-success/10 text-success-foreground border-success/20">In Stock</Badge>;
};

function EmptyInventoryState() {
  return (
    <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
        className="relative bg-primary/10 rounded-full p-6"
      >
        <Package className="h-16 w-16 text-primary" />
        <motion.div
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.4, duration: 0.5 }}
          className="absolute -top-2 -right-2 text-primary"
        >
          <Sparkles className="h-8 w-8" />
        </motion.div>
      </motion.div>
      <h3 className="mt-6 text-xl font-semibold">Your Inventory is Empty</h3>
      <p className="mt-2 text-muted-foreground">
        Import your products to get started with inventory management.
      </p>
      <Button asChild className="mt-6">
        <Link href="/import">Import Inventory</Link>
      </Button>
    </Card>
  );
}

// Group variants by their parent product
const groupVariantsByProduct = (inventory: UnifiedInventoryItem[]) => {
  const productMap: Record<string, { product_id: string; product_title: string; product_status: string, image_url: string | null, variants: UnifiedInventoryItem[], total_quantity: number }> = {};
  
  inventory.forEach(variant => {
    const productId = variant.product_id;
    if (productId === '__proto__') return;

    if (!Object.prototype.hasOwnProperty.call(productMap, productId)) {
      productMap[productId] = {
        product_id: productId,
        product_title: variant.product_title || 'Unknown Product',
        product_status: variant.product_status || 'unknown',
        image_url: variant.image_url,
        variants: [],
        total_quantity: 0
      };
    }
    if (Object.prototype.hasOwnProperty.call(productMap, productId)) {
        productMap[productId].variants.push(variant);
        productMap[productId].total_quantity += variant.inventory_quantity;
    }
  });
  
  return Object.values(productMap);
};

const SortableHeader = ({ column, label, currentSort, currentDirection, onSort }: { column: SortableColumn, label: string, currentSort: SortableColumn, currentDirection: 'asc' | 'desc', onSort: (column: SortableColumn) => void }) => {
    const isActive = column === currentSort;
    return (
        <TableHead className="cursor-pointer" onClick={() => { onSort(column); }}>
            <div className="flex items-center gap-2">
                {label}
                {isActive ? (
                    <ChevronDown className={cn("h-4 w-4 transition-transform", currentDirection === 'asc' && "rotate-180")} />
                ) : (
                    <ArrowDownUp className="h-4 w-4 text-muted-foreground/50" />
                )}
            </div>
        </TableHead>
    );
};


export function InventoryClientPage({ initialInventory, totalCount, itemsPerPage, analyticsData, exportAction }: InventoryClientPageProps) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const replace = router.replace.bind(router);

  const [expandedProducts, setExpandedProducts] = useState(new Set<string>());
  const [historyVariant, setHistoryVariant] = useState<UnifiedInventoryItem | null>(null);

  const query = searchParams.get('query') || '';
  const status = searchParams.get('status') || 'all';
  const sortBy = (searchParams.get('sortBy') ?? 'product_title') as SortableColumn;
  const sortDirection = searchParams.get('sortDirection') === 'desc' ? 'desc' : 'asc';
  
  const createUrlWithParams = (newParams: Record<string, string>) => {
    const params = new URLSearchParams(searchParams);
    Object.entries(newParams).forEach(([key, value]) => {
      if (value) {
        params.set(key, value);
      } else {
        params.delete(key);
      }
    });
    // Reset page on filter/sort change
    params.set('page', '1');
    return `${pathname}?${params.toString()}`;
  }

  const handleSearch = useDebouncedCallback((term: string) => {
    replace(createUrlWithParams({ query: term }));
  }, 300);

  const handleStatusChange = (newStatus: string) => {
    replace(createUrlWithParams({ status: newStatus }));
  };
  
  const handleSort = (column: SortableColumn) => {
    const newDirection = sortBy === column && sortDirection === 'asc' ? 'desc' : 'asc';
    replace(createUrlWithParams({ sortBy: column, sortDirection: newDirection }));
  };

  const toggleExpandProduct = (productId: string) => {
    setExpandedProducts(prev => {
      const newSet = new Set(prev);
      if (newSet.has(productId)) {
        newSet.delete(productId);
      } else {
        newSet.add(productId);
      }
      return newSet;
    });
  };
  
  const groupedInventory = useMemo(() => groupVariantsByProduct(initialInventory), [initialInventory]);
  
  const isFiltered = !!query || status !== 'all';
  const showEmptyState = totalCount === 0 && !isFiltered;
  const showNoResultsState = totalCount === 0 && isFiltered;
  
  const handleExport = () => {
    return exportAction({ query, status, sortBy, sortDirection });
  }

  return (
    <>
    <InventoryHistoryDialog variant={historyVariant} onClose={() => { setHistoryVariant(null); }} />

    <div className="space-y-6">
       <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            <AnalyticsCard title="Total Inventory Value" value={formatCentsAsCurrency(analyticsData.total_inventory_value || 0)} icon={DollarSign} />
            <AnalyticsCard title="Total Products" value={analyticsData.total_products || 0} icon={PackageIcon} />
            <AnalyticsCard title="Total Variants (SKUs)" value={analyticsData.total_variants || 0} icon={PackageIcon} />
            <AnalyticsCard title="Items Low on Stock" value={analyticsData.low_stock_items || 0} icon={AlertTriangle} />
        </div>

      <div className="flex flex-col md:flex-row items-center gap-2">
        <div className="relative flex-1 w-full">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
                placeholder="Search by product title or SKU..."
                onChange={(e) => handleSearch(e.target.value)}
                defaultValue={query}
                className="pl-10"
            />
        </div>
        <div className="flex w-full md:w-auto gap-2 flex-wrap">
            <Select onValueChange={handleStatusChange} defaultValue={status}>
              <SelectTrigger className="w-full md:w-[180px]">
                <SelectValue placeholder="Filter by status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Statuses</SelectItem>
                <SelectItem value="active">Active</SelectItem>
                <SelectItem value="draft">Draft</SelectItem>
                <SelectItem value="archived">Archived</SelectItem>
              </SelectContent>
            </Select>
            <ExportButton exportAction={handleExport} filename="inventory.csv" />
        </div>
      </div>
      
        {showEmptyState ? <EmptyInventoryState /> : (
            <Card>
                <CardContent className="p-0">
                <div className="max-h-[70vh] overflow-auto">
                    <Table>
                        <TableHeader className="sticky top-0 z-10 bg-background/80 backdrop-blur-sm">
                            <TableRow>
                                <SortableHeader column="product_title" label="Product" currentSort={sortBy} currentDirection={sortDirection} onSort={handleSort} />
                                <SortableHeader column="product_status" label="Status" currentSort={sortBy} currentDirection={sortDirection} onSort={handleSort} />
                                <TableHead className="text-right">Variants</TableHead>
                                <SortableHeader column="inventory_quantity" label="Total Quantity" currentSort={sortBy} currentDirection={sortDirection} onSort={handleSort} />
                                <TableHead className="w-16 text-center">Actions</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                        {showNoResultsState ? (
                            <TableRow>
                                <TableCell colSpan={5} className="h-24 text-center">
                                    No inventory found matching your criteria.
                                </TableCell>
                            </TableRow>
                        ) : groupedInventory.map(product => {
                            const totalQty = product.variants.reduce((sum, v) => sum + v.inventory_quantity, 0);
                            return (
                            <Fragment key={product.product_id}>
                            <TableRow className="group transition-shadow data-[state=selected]:bg-muted hover:shadow-md">
                                <TableCell>
                                    <div className="flex items-center gap-3">
                                        <Avatar className="h-10 w-10 rounded-md">
                                            <AvatarImage src={product.image_url || undefined} alt={product.product_title} />
                                            <AvatarFallback className="rounded-md bg-muted text-muted-foreground">{product.product_title.charAt(0)}</AvatarFallback>
                                        </Avatar>
                                        <div className="font-medium">{product.product_title}</div>
                                    </div>
                                </TableCell>
                                <TableCell><Badge variant={product.product_status === 'active' ? 'secondary' : 'outline'} className={cn(
                                    product.product_status === 'active' ? 'bg-success/10 text-success-foreground' : 
                                    product.product_status === 'draft' ? 'bg-warning/10 text-amber-600 dark:text-amber-400' : 'bg-gray-500/10 text-gray-500'
                                    )}>{product.product_status}</Badge></TableCell>
                                <TableCell className="text-right font-tabular">{product.variants.length}</TableCell>
                                <TableCell className="text-right font-semibold font-tabular">{totalQty}</TableCell>
                                <TableCell className="text-center">
                                    <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => { toggleExpandProduct(product.product_id); }}>
                                        <ChevronDown className={cn("h-4 w-4 transition-transform", expandedProducts.has(product.product_id) && "rotate-180")} />
                                    </Button>
                                </TableCell>
                            </TableRow>
                            {expandedProducts.has(product.product_id) && (
                                <TableRow className="bg-muted/50 hover:bg-muted/80">
                                    <TableCell colSpan={5} className="p-0">
                                        <div className="p-4">
                                            <div className="rounded-md border bg-card">
                                                <Table>
                                                    <TableHeader>
                                                        <TableRow>
                                                            <TableHead>Variant</TableHead>
                                                            <TableHead>SKU</TableHead>
                                                            <TableHead className="text-right">Price</TableHead>
                                                            <TableHead className="text-right">Cost</TableHead>
                                                            <TableHead className="text-right">Quantity</TableHead>
                                                            <TableHead>Status</TableHead>
                                                            <TableHead>Location</TableHead>
                                                            <TableHead className="text-center">Actions</TableHead>
                                                        </TableRow>
                                                    </TableHeader>
                                                    <TableBody>
                                                        {product.variants.map(variant => (
                                                            <TableRow key={variant.id} className="hover:bg-background">
                                                                <TableCell>{variant.title || 'Default'}</TableCell>
                                                                <TableCell className="text-muted-foreground">{variant.sku}</TableCell>
                                                                <TableCell className="text-right font-tabular">{formatCentsAsCurrency(variant.price)}</TableCell>
                                                                <TableCell className="text-right font-tabular">{formatCentsAsCurrency(variant.cost)}</TableCell>
                                                                <TableCell className="text-right font-medium font-tabular">{variant.inventory_quantity}</TableCell>
                                                                <TableCell><StatusBadge quantity={variant.inventory_quantity} /></TableCell>
                                                                <TableCell>{variant.location || 'N/A'}</TableCell>
                                                                <TableCell className="text-center space-x-1">
                                                                    <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => { setHistoryVariant(variant); }}>
                                                                        <History className="h-4 w-4" />
                                                                    </Button>
                                                                </TableCell>
                                                            </TableRow>
                                                        ))}
                                                    </TableBody>
                                                </Table>
                                            </div>
                                        </div>
                                    </TableCell>
                                </TableRow>
                            )}
                            </Fragment>
                        )})}
                        </TableBody>
                    </Table>
                </div>
                <PaginationControls totalCount={totalCount} itemsPerPage={itemsPerPage} />
                </CardContent>
            </Card>
        )}
    </div>
    </>
  );
}
