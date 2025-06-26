'use client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Download, Search, Package, AlertTriangle } from 'lucide-react';
import { useState, useEffect, useMemo, useCallback } from 'react';
import type { InventoryItem } from '@/types';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { Skeleton } from '@/components/ui/skeleton';
import { useToast } from '@/hooks/use-toast';
import { getInventoryData } from '@/app/data-actions';
import { format, parseISO } from 'date-fns';
import Link from 'next/link';

function InventorySkeleton() {
  return Array.from({ length: 8 }).map((_, i) => (
    <TableRow key={i}>
      <TableCell><Skeleton className="h-4 w-20" /></TableCell>
      <TableCell><Skeleton className="h-4 w-48" /></TableCell>
      <TableCell><Skeleton className="h-4 w-24" /></TableCell>
      <TableCell><Skeleton className="h-4 w-16" /></TableCell>
      <TableCell><Skeleton className="h-4 w-24" /></TableCell>
      <TableCell><Skeleton className="h-4 w-24" /></TableCell>
      <TableCell><Skeleton className="h-4 w-24" /></TableCell>
    </TableRow>
  ));
}

export default function InventoryPage() {
  const [search, setSearch] = useState('');
  const [allInventory, setAllInventory] = useState<InventoryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { toast } = useToast();

  const fetchData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await getInventoryData();
      setAllInventory(data);
    } catch (err: any) {
      console.error("Failed to fetch inventory", err);
      const errorMessage = err.message || 'Could not load inventory data.';
      setError(errorMessage);
      toast({ variant: 'destructive', title: 'Error', description: errorMessage });
    } finally {
      setLoading(false);
    }
  }, [toast]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const filteredInventory = useMemo(() => {
    if (!search) return allInventory;
    return allInventory.filter((item) =>
      item.name.toLowerCase().includes(search.toLowerCase())
    );
  }, [allInventory, search]);


  return (
    <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Inventory</h1>
        </div>
        <Button>
          <Download className="mr-2 h-4 w-4" />
          Export to CSV
        </Button>
      </div>

      <div className="space-y-4">
        <div className="flex flex-col md:flex-row gap-4">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search by name..."
              className="pl-10"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              disabled={loading || !!error}
            />
          </div>
          <Select disabled>
            <SelectTrigger className="w-full md:w-[180px]">
              <SelectValue placeholder="All Categories" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="electronics">Electronics</SelectItem>
              <SelectItem value="furniture">Furniture</SelectItem>
               <SelectItem value="office-supplies">Office Supplies</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>SKU</TableHead>
                <TableHead>Name</TableHead>
                <TableHead>Category</TableHead>
                <TableHead className="text-right">Quantity</TableHead>
                <TableHead className="text-right">Unit Cost</TableHead>
                <TableHead>Last Sold</TableHead>
                <TableHead>Warehouse</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loading ? (
                <InventorySkeleton />
              ) : error ? (
                <TableRow>
                    <TableCell colSpan={7}>
                        <div className="flex flex-col items-center justify-center gap-4 py-12 text-center text-destructive">
                            <AlertTriangle className="h-16 w-16" />
                            <h3 className="text-xl font-semibold">An Error Occurred</h3>
                            <p className="max-w-md">{error}</p>
                            <Button onClick={() => fetchData()} variant="destructive">Try Again</Button>
                        </div>
                    </TableCell>
                </TableRow>
              ) : filteredInventory.length > 0 ? (
                filteredInventory.map((item) => (
                  <TableRow key={item.id}>
                    <TableCell className="font-mono text-xs">
                      {item.sku}
                    </TableCell>
                    <TableCell className="font-medium">{item.name}</TableCell>
                    <TableCell>{item.category}</TableCell>
                    <TableCell className="text-right">
                      {item.quantity}
                    </TableCell>
                    <TableCell className="text-right">
                      ${Number(item.cost).toLocaleString()}
                    </TableCell>
                    <TableCell>{item.last_sold_date ? format(parseISO(item.last_sold_date), 'yyyy-MM-dd') : 'N/A'}</TableCell>
                    <TableCell>{item.warehouse_name || 'N/A'}</TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={7}>
                    <div className="flex flex-col items-center justify-center gap-4 py-12 text-center">
                        <Package className="h-16 w-16 text-muted-foreground" />
                        <h3 className="text-xl font-semibold">Your Inventory is Empty</h3>
                        <p className="text-muted-foreground">You can start by importing your product list.</p>
                        <Button asChild>
                            <Link href="/import">Import Data</Link>
                        </Button>
                    </div>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </div>
      </div>
    </div>
  );
}
