
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
import { Download, Search, AlertTriangle } from 'lucide-react';
import { useState, useEffect, useMemo, useCallback } from 'react';
import type { InventoryItem } from '@/types';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { Skeleton } from '@/components/ui/skeleton';
import { useToast } from '@/hooks/use-toast';
import { getInventoryData } from '@/app/data-actions';
import { format, parseISO } from 'date-fns';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import { useAuth } from '@/context/auth-context';
import Papa from 'papaparse';


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

function EmptyState() {
    return (
        <TableRow>
            <TableCell colSpan={7}>
                <motion.div
                    initial={{ opacity: 0, scale: 0.95 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ duration: 0.5, ease: 'easeOut' }}
                    className="flex flex-col items-center justify-center gap-4 text-center rounded-lg border-2 border-dashed bg-card/50 py-24"
                >
                    <div className="w-32 h-32">
                        <svg viewBox="0 0 128 128" fill="none" xmlns="http://www.w3.org/2000/svg">
                            <path d="M40 40H88C92.4183 40 96 43.5817 96 48V96C96 100.418 92.4183 104 88 104H40C35.5817 104 32 100.418 32 96V48C32 43.5817 35.5817 40 40 40Z" stroke="hsl(var(--primary))" strokeOpacity="0.2" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round"/>
                            <motion.path
                                initial={{ pathLength: 0 }}
                                animate={{ pathLength: 1 }}
                                transition={{ duration: 1, delay: 0.2, ease: "circOut" }}
                                d="M64 24V40" stroke="hsl(var(--primary))" strokeOpacity="0.4" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round"/>
                            <motion.path
                                initial={{ pathLength: 0 }}
                                animate={{ pathLength: 1 }}
                                transition={{ duration: 1, delay: 0.2, ease: "circOut" }}
                                d="M104 64H88" stroke="hsl(var(--primary))" strokeOpacity="0.4" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round"/>
                            <motion.path
                                initial={{ pathLength: 0 }}
                                animate={{ pathLength: 1 }}
                                transition={{ duration: 1, delay: 0.2, ease: "circOut" }}
                                d="M64 104V88" stroke="hsl(var(--primary))" strokeOpacity="0.4" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round"/>
                            <motion.path
                                initial={{ pathLength: 0 }}
                                animate={{ pathLength: 1 }}
                                transition={{ duration: 1, delay: 0.2, ease: "circOut" }}
                                d="M24 64H40" stroke="hsl(var(--primary))" strokeOpacity="0.4" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round"/>
                            <motion.g
                                initial={{ opacity: 0, scale: 0.5 }}
                                animate={{ opacity: 1, scale: 1 }}
                                transition={{ type: 'spring', stiffness: 200, damping: 10, delay: 0.8 }}
                            >
                                <path d="M76 52H52C50.8954 52 50 52.8954 50 54V78C50 79.1046 50.8954 80 52 80H76C77.1046 80 78 79.1046 78 78V54C78 52.8954 77.1046 52 76 52Z" fill="hsl(var(--primary))" fillOpacity="0.1"/>
                                <path d="M76 52H52C50.8954 52 50 52.8954 50 54V78C50 79.1046 50.8954 80 52 80H76C77.1046 80 78 79.1046 78 78V54C78 52.8954 77.1046 52 76 52Z" stroke="hsl(var(--primary))" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round"/>
                                <path d="M64 60V72" stroke="hsl(var(--primary-foreground))" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round"/>
                                <path d="M58 66H70" stroke="hsl(var(--primary-foreground))" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round"/>
                            </motion.g>
                        </svg>
                    </div>
                    <h3 className="mt-2 text-2xl font-semibold tracking-tight">Your inventory is empty</h3>
                    <p className="max-w-xs text-muted-foreground">Get started by importing your products. It's fast and easy!</p>
                    <Button asChild className="mt-4">
                        <Link href="/import">Import Data</Link>
                    </Button>
                </motion.div>
            </TableCell>
        </TableRow>
    );
}

function NoResultsState({ setSearch, setCategory }: { setSearch: (search: string) => void, setCategory: (category: string) => void }) {
    const handleClear = () => {
        setSearch('');
        setCategory('all');
    };
    return (
        <TableRow>
            <TableCell colSpan={7}>
                <motion.div 
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.3, ease: 'easeOut' }}
                    className="flex flex-col items-center justify-center gap-4 text-center rounded-lg border-2 border-dashed bg-card/50 py-24"
                >
                    <Search className="h-16 w-16 text-muted-foreground" />
                    <h3 className="mt-2 text-2xl font-semibold tracking-tight">No Products Found</h3>
                    <p className="max-w-xs text-muted-foreground">Your search and filter combination did not match any products.</p>
                    <Button onClick={handleClear} variant="outline" className="mt-4">
                        Clear Filters
                    </Button>
                </motion.div>
            </TableCell>
        </TableRow>
    );
}


export default function InventoryPage() {
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('all');
  const [allInventory, setAllInventory] = useState<InventoryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { toast } = useToast();
  const { user } = useAuth();

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

  // Realtime subscription effect
  useEffect(() => {
    const companyId = user?.app_metadata?.company_id;
    if (!companyId) return;

    const supabase = createBrowserSupabaseClient();
    const channel = supabase
      .channel(`inventory-changes-for-${companyId}`)
      .on(
        'postgres_changes',
        { 
          event: '*', 
          schema: 'public', 
          table: 'inventory',
          filter: `company_id=eq.${companyId}`
        },
        (payload) => {
          const { eventType, new: newItem, old: oldItem } = payload;
          
          setAllInventory(currentInventory => {
              if (eventType === 'INSERT') {
                  return [...currentInventory, newItem as InventoryItem];
              }
              if (eventType === 'UPDATE') {
                  return currentInventory.map(item => item.id === newItem.id ? newItem as InventoryItem : item);
              }
              if (eventType === 'DELETE') {
                  return currentInventory.filter(item => item.id !== (oldItem as InventoryItem).id);
              }
              return currentInventory;
          });
        }
      )
      .subscribe((status, err) => {
        if (status === 'SUBSCRIBED') {
            console.log('Successfully subscribed to real-time inventory updates!');
        }
        if (err) {
            console.error('Realtime subscription error:', err);
            toast({
                variant: 'destructive',
                title: 'Real-time Error',
                description: 'Could not connect to live updates. Changes may not appear automatically.',
            });
        }
      });

    return () => {
      supabase.removeChannel(channel);
    };
  }, [user, toast]);

  const categories = useMemo(() => {
    const uniqueCategories = [...new Set(allInventory.map(item => item.category).filter(Boolean) as string[])];
    return ['all', ...uniqueCategories.sort()];
  }, [allInventory]);

  const filteredInventory = useMemo(() => {
    return allInventory.filter((item) => {
        const matchesCategory = category === 'all' || item.category === category;
        const matchesSearch = !search || item.name.toLowerCase().includes(search.toLowerCase());
        return matchesCategory && matchesSearch;
    });
  }, [allInventory, search, category]);
  
  const handleExport = () => {
    if (filteredInventory.length === 0) {
        toast({
            variant: 'destructive',
            title: 'No Data to Export',
            description: 'There are no items in the current view to export.',
        });
        return;
    }
    const csv = Papa.unparse(filteredInventory);
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    const url = URL.createObjectURL(blob);
    link.setAttribute('href', url);
    link.setAttribute('download', 'inventory_export.csv');
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };


  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Inventory</h1>
        </div>
        <Button onClick={handleExport} disabled={loading || !!error}>
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
          <Select value={category} onValueChange={setCategory} disabled={loading || !!error || categories.length <= 1}>
            <SelectTrigger className="w-full md:w-[180px]">
              <SelectValue placeholder="All Categories" />
            </SelectTrigger>
            <SelectContent>
                {categories.map((cat) => (
                    <SelectItem key={cat} value={cat} className="capitalize">{cat === 'all' ? 'All Categories' : cat}</SelectItem>
                ))}
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
              ) : allInventory.length === 0 ? (
                <EmptyState />
              ) : filteredInventory.length === 0 ? (
                <NoResultsState setSearch={setSearch} setCategory={setCategory} />
              ) : (
                filteredInventory.map((item) => (
                  <TableRow key={item.id}>
                    <TableCell className="font-mono text-xs">
                      {item.sku}
                    </TableCell>
                    <TableCell className="font-medium">{item.name}</TableCell>
                    <TableCell className="capitalize">{item.category}</TableCell>
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
              )}
            </TableBody>
          </Table>
        </div>
      </div>
    </div>
  );
}

    