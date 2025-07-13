

'use client';

import { useState, useMemo, Fragment, useTransition, useEffect } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { useDebouncedCallback } from 'use-debounce';
import Link from 'next/link';
import { Input } from '@/components/ui/input';
import type { UnifiedInventoryItem, Supplier, InventoryAnalytics } from '@/types';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Search, ChevronDown, Package as PackageIcon, AlertTriangle, DollarSign, TrendingUp, Sparkles } from 'lucide-react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { motion } from 'framer-motion';
import { cn } from '@/lib/utils';
import { Package } from 'lucide-react';
import { ExportButton } from '@/components/ui/export-button';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { formatCentsAsCurrency } from '@/lib/utils';


interface InventoryClientPageProps {
  initialInventory: UnifiedInventoryItem[];
  totalCount: number;
  itemsPerPage: number;
  analyticsData: InventoryAnalytics;
  exportAction: () => Promise<{ success: boolean; data?: string; error?: string }>;
}

const AnalyticsCard = ({ title, value, icon: Icon, label }: { title: string, value: string | number, icon: React.ElementType, label?: string }) => (
    <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
            <Icon className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
            <div className="text-2xl font-bold">{typeof value === 'number' && !Number.isInteger(value) ? formatCentsAsCurrency(value) : value}</div>
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
                    onClick={() => router.push(createPageURL(currentPage - 1))}
                    disabled={currentPage <= 1}
                >
                    Previous
                </Button>
                <Button
                    variant="outline"
                    onClick={() => router.push(createPageURL(currentPage + 1))}
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
    return <Badge variant="secondary" className="bg-success/10 text-emerald-600 dark:text-emerald-400 border-success/20">In Stock</Badge>;
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
  return inventory.reduce((acc, variant) => {
    const { product_id, product_title, product_status, image_url } = variant;
    if (!acc[product_id]) {
      acc[product_id] = { product_id, product_title, product_status, image_url, variants: [] };
    }
    acc[product_id].variants.push(variant);
    return acc;
  }, {} as Record<string, { product_id: string; product_title: string; product_status: string, image_url: string | null, variants: UnifiedInventoryItem[] }>);
};


export function InventoryClientPage({ initialInventory, totalCount, itemsPerPage, analyticsData, exportAction }: InventoryClientPageProps) {
  const searchParams = useSearchParams();
  const pathname = usePathname();
  const { replace } = useRouter();

  const [expandedProducts, setExpandedProducts] = useState(new Set<string>());

  const handleSearch = useDebouncedCallback((term: string) => {
    const params = new URLSearchParams(searchParams);
    params.set('page', '1'); 
    if (term) {
      params.set('query', term);
    } else {
      params.delete('query');
    }
    replace(`${pathname}?${params.toString()}`);
  }, 300);

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
  
  const isFiltered = !!searchParams.get('query');
  const showEmptyState = totalCount === 0 && !isFiltered;
  const showNoResultsState = totalCount === 0 && isFiltered;
  
  return (
    <div className="space-y-6">
       <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            <AnalyticsCard title="Total Inventory Value" value={analyticsData.total_inventory_value || '$0'} icon={DollarSign} />
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
                defaultValue={searchParams.get('query')?.toString()}
                className="pl-10"
            />
        </div>
        <div className="flex w-full md:w-auto gap-2 flex-wrap">
            <ExportButton exportAction={exportAction} filename="inventory.csv" />
        </div>
      </div>
      
        {showEmptyState ? <EmptyInventoryState /> : (
            <Card>
                <CardContent className="p-0">
                <div className="max-h-[70vh] overflow-auto">
                    <Table>
                        <TableHeader className="sticky top-0 z-10 bg-background/80 backdrop-blur-sm">
                            <TableRow>
                                <TableHead>Product</TableHead>
                                <TableHead>Status</TableHead>
                                <TableHead className="text-right">Variants</TableHead>
                                <TableHead className="text-right">Total Quantity</TableHead>
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
                        ) : Object.values(groupedInventory).map(product => {
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
                                <TableCell><Badge variant={product.product_status === 'active' ? 'secondary' : 'outline'} className={product.product_status === 'active' ? 'bg-success/10 text-success' : ''}>{product.product_status}</Badge></TableCell>
                                <TableCell className="text-right">{product.variants.length}</TableCell>
                                <TableCell className="text-right font-semibold">{totalQty}</TableCell>
                                <TableCell className="text-center">
                                    <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => toggleExpandProduct(product.product_id)}>
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
                                                        </TableRow>
                                                    </TableHeader>
                                                    <TableBody>
                                                        {product.variants.map(variant => (
                                                            <TableRow key={variant.id} className="hover:bg-background">
                                                                <TableCell>{variant.title || 'Default'}</TableCell>
                                                                <TableCell className="text-muted-foreground">{variant.sku}</TableCell>
                                                                <TableCell className="text-right">{formatCentsAsCurrency(variant.price)}</TableCell>
                                                                <TableCell className="text-right">{formatCentsAsCurrency(variant.cost)}</TableCell>
                                                                <TableCell className="text-right font-medium">{variant.inventory_quantity}</TableCell>
                                                                <TableCell><StatusBadge quantity={variant.inventory_quantity} /></TableCell>
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
  );
}
