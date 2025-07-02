
'use client';

import { useState, useMemo, Fragment, useTransition, useEffect } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { useDebouncedCallback } from 'use-debounce';
import Link from 'next/link';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import type { UnifiedInventoryItem, Location, Supplier } from '@/types';
import { Card, CardContent } from '@/components/ui/card';
import { Search, MoreHorizontal, ChevronDown, Trash2, Edit, Sparkles, Loader2, Warehouse, History, X } from 'lucide-react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Checkbox } from '@/components/ui/checkbox';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { motion, AnimatePresence } from 'framer-motion';
import { cn } from '@/lib/utils';
import { useToast } from '@/hooks/use-toast';
import { deleteInventoryItems } from '@/app/data-actions';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '../ui/alert-dialog';
import { InventoryEditDialog } from './inventory-edit-dialog';
import { Package } from 'lucide-react';
import { InventoryHistoryDialog } from './inventory-history-dialog';
import { TooltipProvider, Tooltip, TooltipTrigger, TooltipContent } from '../ui/tooltip';


interface InventoryClientPageProps {
  initialInventory: UnifiedInventoryItem[];
  categories: string[];
  locations: Location[];
  suppliers: Supplier[];
}

const StatusBadge = ({ quantity, reorderPoint }: { quantity: number, reorderPoint: number | null }) => {
    if (quantity <= 0) {
        return <Badge variant="destructive" className="bg-destructive/10 text-destructive border-destructive/20">Out of Stock</Badge>;
    }
    if (reorderPoint !== null && quantity < reorderPoint) {
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


export function InventoryClientPage({ initialInventory, categories, locations, suppliers }: InventoryClientPageProps) {
  const searchParams = useSearchParams();
  const pathname = usePathname();
  const { replace, refresh } = useRouter();
  const { toast } = useToast();

  const [inventory, setInventory] = useState(initialInventory);
  const [selectedRows, setSelectedRows] = useState(new Set<string>());
  const [expandedRows, setExpandedRows] = useState(new Set<string>());
  const [isDeleting, startDeleteTransition] = useTransition();
  const [itemToDelete, setItemToDelete] = useState<string[] | null>(null);
  const [editingItem, setEditingItem] = useState<UnifiedInventoryItem | null>(null);
  const [historySku, setHistorySku] = useState<string | null>(null);

  // This effect ensures the component's state stays in sync with the server-provided data
  // when filters are applied via URL changes.
  useEffect(() => {
    setInventory(initialInventory);
  }, [initialInventory]);

  const handleSearch = useDebouncedCallback((term: string) => {
    const params = new URLSearchParams(searchParams);
    if (term) {
      params.set('query', term);
    } else {
      params.delete('query');
    }
    replace(`${pathname}?${params.toString()}`);
  }, 300);

  const handleFilterChange = (type: 'category' | 'location' | 'supplier', value: string) => {
    const params = new URLSearchParams(searchParams);
    if (value && value !== 'all') {
      params.set(type, value);
    } else {
      params.delete(type);
    }
    replace(`${pathname}?${params.toString()}`);
  };

  const handleSelectAll = (checked: boolean | 'indeterminate') => {
    if (checked === true) {
      setSelectedRows(new Set(inventory.map(item => item.sku)));
    } else {
      setSelectedRows(new Set());
    }
  };

  const handleSelectRow = (sku: string, checked: boolean) => {
    const newSelectedRows = new Set(selectedRows);
    if (checked) {
      newSelectedRows.add(sku);
    } else {
      newSelectedRows.delete(sku);
    }
    setSelectedRows(newSelectedRows);
  };
  
  const handleDelete = () => {
    if (!itemToDelete) return;
    startDeleteTransition(async () => {
      const result = await deleteInventoryItems(itemToDelete);
      if (result.success) {
        toast({ title: 'Success', description: `${itemToDelete.length} item(s) deleted.` });
        refresh(); // Refresh from server to ensure consistency
        setSelectedRows(new Set());
      } else {
        toast({ variant: 'destructive', title: 'Error', description: result.error });
      }
      setItemToDelete(null);
    });
  };

  const toggleExpandRow = (sku: string) => {
    const newExpandedRows = new Set(expandedRows);
    if (newExpandedRows.has(sku)) {
      newExpandedRows.delete(sku);
    } else {
      newExpandedRows.add(sku);
    }
    setExpandedRows(newExpandedRows);
  };

  const handleSaveItem = (updatedItem: UnifiedInventoryItem) => {
    setInventory(prev => prev.map(item => item.sku === updatedItem.sku ? updatedItem : item));
    refresh(); // Refresh from server to ensure consistency
  };


  const numSelected = selectedRows.size;
  const numInventory = inventory.length;
  const isAllSelected = numSelected > 0 && numSelected === numInventory;
  const isSomeSelected = numSelected > 0 && numSelected < numInventory;
  
  const isFiltered = !!searchParams.get('query') || !!searchParams.get('category') || !!searchParams.get('location') || !!searchParams.get('supplier');
  const showEmptyState = inventory.length === 0 && !isFiltered;
  const showNoResultsState = inventory.length === 0 && isFiltered;
  
  return (
    <div className="space-y-4">
      <div className="flex flex-col md:flex-row items-center gap-2">
        <div className="relative flex-1 w-full">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
                placeholder="Search by product name or SKU..."
                onChange={(e) => handleSearch(e.target.value)}
                defaultValue={searchParams.get('query')?.toString()}
                className="pl-10"
            />
        </div>
        <div className="flex w-full md:w-auto gap-2 flex-wrap">
            <Select
                onValueChange={(value) => handleFilterChange('supplier', value)}
                defaultValue={searchParams.get('supplier') || 'all'}
            >
              <SelectTrigger className="w-full md:w-[200px]">
                <SelectValue placeholder="Filter by supplier" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Suppliers</SelectItem>
                {suppliers.map((supplier) => (
                  <SelectItem key={supplier.id} value={supplier.id}>
                    {supplier.vendor_name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select
                onValueChange={(value) => handleFilterChange('location', value)}
                defaultValue={searchParams.get('location') || 'all'}
            >
              <SelectTrigger className="w-full md:w-[200px]">
                <SelectValue placeholder="Filter by location" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Locations</SelectItem>
                {locations.map((location) => (
                  <SelectItem key={location.id} value={location.id}>
                    {location.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select
                onValueChange={(value) => handleFilterChange('category', value)}
                defaultValue={searchParams.get('category') || 'all'}
            >
              <SelectTrigger className="w-full md:w-[200px]">
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
      </div>
      
      <AlertDialog open={!!itemToDelete} onOpenChange={(open) => !open && setItemToDelete(null)}>
        <AlertDialogContent>
            <AlertDialogHeader>
                <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
                <AlertDialogDescription>
                    This action will attempt to permanently delete the selected {itemToDelete?.length} item(s). This will fail if an item is part of any past sales or purchase orders, to protect your data integrity.
                </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
                <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
                <AlertDialogAction onClick={handleDelete} disabled={isDeleting} className="bg-destructive hover:bg-destructive/90">
                    {isDeleting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Yes, delete
                </AlertDialogAction>
            </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <InventoryEditDialog
        item={editingItem}
        onClose={() => setEditingItem(null)}
        onSave={handleSaveItem}
        locations={locations}
      />

       <InventoryHistoryDialog
            sku={historySku}
            onClose={() => setHistorySku(null)}
       />

        {showEmptyState ? <EmptyInventoryState /> : (
            <Card>
                <CardContent className="p-0">
                <div className="max-h-[65vh] overflow-auto">
                    <Table>
                        <TableHeader className="sticky top-0 z-10 bg-background/80 backdrop-blur-sm">
                        <TableRow>
                            <TableHead className="w-12">
                            <Checkbox
                                checked={isAllSelected ? true : (isSomeSelected ? 'indeterminate' : false)}
                                onCheckedChange={handleSelectAll}
                            />
                            </TableHead>
                            <TableHead>Product</TableHead>
                            <TableHead>Location</TableHead>
                            <TableHead className="text-right">Quantity</TableHead>
                            <TableHead className="text-right">Total Value</TableHead>
                            <TableHead className="text-right">Profit Margin</TableHead>
                            <TableHead className="text-right">Monthly Profit</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="w-24 text-center">Actions</TableHead>
                        </TableRow>
                        </TableHeader>
                        <TableBody>
                        {showNoResultsState ? (
                            <TableRow>
                                <TableCell colSpan={9} className="h-24 text-center">
                                    No inventory found matching your criteria.
                                </TableCell>
                            </TableRow>
                        ) : inventory.map(item => {
                            const price = item.price || 0;
                            const cost = item.landed_cost || item.cost || 0;
                            const margin = price > 0 ? ((price - cost) / price) * 100 : 0;
                            const marginColor = margin > 30 ? 'text-success' : margin > 15 ? 'text-amber-500' : 'text-destructive';
                            const monthlyProfit = item.monthly_profit || 0;
                            const profitColor = monthlyProfit > 0 ? 'text-success' : monthlyProfit < 0 ? 'text-destructive' : 'text-muted-foreground';

                            return (
                            <Fragment key={item.sku}>
                            <TableRow className="group transition-shadow data-[state=selected]:bg-muted hover:shadow-md">
                                <TableCell>
                                <Checkbox
                                    checked={selectedRows.has(item.sku)}
                                    onCheckedChange={(checked) => handleSelectRow(item.sku, !!checked)}
                                />
                                </TableCell>
                                <TableCell>
                                <div className="font-medium">{item.product_name}</div>
                                <div className="text-xs text-muted-foreground">{item.sku}</div>
                                </TableCell>
                                <TableCell>{item.location_name || <span className="text-muted-foreground italic">Unassigned</span>}</TableCell>
                                <TableCell className="text-right">{item.quantity}</TableCell>
                                <TableCell className="text-right font-medium">${item.total_value.toFixed(2)}</TableCell>
                                <TableCell className="text-right">
                                    <span className={cn('font-semibold', marginColor)}>{margin.toFixed(1)}%</span>
                                </TableCell>
                                <TableCell className="text-right">
                                     <span className={cn('font-semibold', profitColor)}>{monthlyProfit >= 0 ? '$' : '-$'}{Math.abs(monthlyProfit).toFixed(2)}</span>
                                </TableCell>
                                <TableCell>
                                <StatusBadge quantity={item.quantity} reorderPoint={item.reorder_point} />
                                </TableCell>
                                <TableCell className="text-center">
                                    <div className="flex items-center justify-center">
                                    <DropdownMenu>
                                            <DropdownMenuTrigger asChild>
                                                <Button variant="ghost" size="icon" className="h-8 w-8">
                                                    <MoreHorizontal className="h-4 w-4" />
                                                </Button>
                                            </DropdownMenuTrigger>
                                            <DropdownMenuContent align="end">
                                                <DropdownMenuItem onSelect={() => setEditingItem(item)}><Edit className="mr-2 h-4 w-4" />Edit</DropdownMenuItem>
                                                <DropdownMenuItem onSelect={() => setHistorySku(item.sku)}><History className="mr-2 h-4 w-4" />View History</DropdownMenuItem>
                                                <DropdownMenuItem onSelect={() => setItemToDelete([item.sku])} className="text-destructive">
                                                  <Trash2 className="mr-2 h-4 w-4" />Delete
                                                </DropdownMenuItem>
                                            </DropdownMenuContent>
                                        </DropdownMenu>
                                        <Button
                                            variant="ghost"
                                            size="icon"
                                            className="h-8 w-8"
                                            onClick={() => toggleExpandRow(item.sku)}
                                        >
                                            <ChevronDown className={cn("h-4 w-4 transition-transform", expandedRows.has(item.sku) && "rotate-180")} />
                                        </Button>
                                    </div>
                                </TableCell>
                            </TableRow>
                            {expandedRows.has(item.sku) && (
                                <TableRow className="bg-muted/50 hover:bg-muted/80">
                                    <TableCell colSpan={9} className="p-4">
                                        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                                            <div><strong className="text-muted-foreground">Category:</strong> {item.category || 'N/A'}</div>
                                            <div><strong className="text-muted-foreground">Unit Cost:</strong> ${item.cost.toFixed(2)}</div>
                                            <div><strong className="text-muted-foreground">Landed Cost:</strong> {item.landed_cost ? `$${item.landed_cost.toFixed(2)}` : 'N/A'}</div>
                                            <div><strong className="text-muted-foreground">On Order:</strong> {item.on_order_quantity} units</div>
                                            <div><strong className="text-muted-foreground">Barcode:</strong> {item.barcode || 'N/A'}</div>
                                            <div><strong className="text-muted-foreground">Monthly Units Sold:</strong> {item.monthly_units_sold}</div>
                                        </div>
                                    </TableCell>
                                </TableRow>
                            )}
                            </Fragment>
                        )})}
                        </TableBody>
                    </Table>
                </div>
                </CardContent>
            </Card>
        )}
      
       <AnimatePresence>
            {numSelected > 0 && (
                <motion.div
                    initial={{ y: 100, opacity: 0 }}
                    animate={{ y: 0, opacity: 1 }}
                    exit={{ y: 100, opacity: 0 }}
                    transition={{ type: 'spring', stiffness: 300, damping: 30 }}
                    className="fixed bottom-4 left-1/2 -translate-x-1/2 w-auto"
                >
                    <div className="flex items-center gap-4 bg-background/80 backdrop-blur-lg border rounded-full p-2 pl-4 shadow-2xl">
                        <p className="text-sm font-medium">{numSelected} item(s) selected</p>
                        <Button variant="destructive" size="sm" onClick={() => setItemToDelete(Array.from(selectedRows))}>Delete Selected</Button>
                        <TooltipProvider>
                            <Tooltip>
                                <TooltipTrigger asChild>
                                    <Button variant="ghost" size="icon" className="rounded-full" onClick={() => setSelectedRows(new Set())}>
                                        <X className="h-4 w-4"/>
                                    </Button>
                                </TooltipTrigger>
                                <TooltipContent>
                                    <p>Deselect All</p>
                                </TooltipContent>
                            </Tooltip>
                        </TooltipProvider>
                    </div>
                </motion.div>
            )}
        </AnimatePresence>
    </div>
  );
}
