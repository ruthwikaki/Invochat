'use client';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { useAuth } from '@/context/auth-context';
import { DollarSign, Package, TrendingDown } from 'lucide-react';
import { useState, useEffect } from 'react';
import { getDeadStockData } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import type { InventoryItem } from '@/types';
import { Skeleton } from '@/components/ui/skeleton';

export default function DeadStockPage() {
  const [data, setData] = useState<{ deadStockItems: InventoryItem[], totalDeadStockValue: number } | null>(null);
  const [loading, setLoading] = useState(true);
  const { user, session } = useAuth();
  const { toast } = useToast();

  useEffect(() => {
    if (user && session) {
      const fetchData = async () => {
        setLoading(true);
        try {
          const token = session.access_token;
          const result = await getDeadStockData(token);
          setData(result);
        } catch (error) {
          console.error("Failed to fetch dead stock data:", error);
          toast({ variant: 'destructive', title: 'Error', description: 'Could not load dead stock data.' });
        } finally {
          setLoading(false);
        }
      };
      fetchData();
    }
  }, [user, session, toast]);

  return (
    <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
       <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Dead Stock</h1>
        </div>
      </div>
      
      <Card className="border-destructive/50 text-destructive">
        <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle>Total Dead Stock Value</CardTitle>
            <DollarSign className="h-5 w-5 text-destructive" />
        </CardHeader>
        <CardContent>
          {loading ? (
            <Skeleton className="h-8 w-1/3" />
          ) : (
            <div className="text-3xl font-bold">${(data?.totalDeadStockValue || 0).toLocaleString()}</div>
          )}
          <p className="text-xs">Across {data?.deadStockItems.length || 0} items</p>
        </CardContent>
      </Card>

      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        {loading ? (
          Array.from({ length: 3 }).map((_, i) => (
            <Card key={i}>
              <CardHeader><Skeleton className="h-6 w-3/4" /></CardHeader>
              <CardContent className="space-y-2">
                <Skeleton className="h-4 w-full" />
                <Skeleton className="h-4 w-full" />
                <Skeleton className="h-4 w-2/3" />
              </CardContent>
              <CardFooter><Skeleton className="h-8 w-24" /></CardFooter>
            </Card>
          ))
        ) : data?.deadStockItems.length === 0 ? (
          <p className="md:col-span-2 lg:col-span-3 text-center text-muted-foreground">No dead stock items found. Great job!</p>
        ) : (
          data?.deadStockItems.map((item) => (
            <Card key={item.id}>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Package className="h-5 w-5" />
                  {item.name}
                </CardTitle>
                <CardDescription>SKU: {item.id}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-2">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Quantity:</span>
                  <span className="font-medium">{item.quantity}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Value:</span>
                  <span className="font-medium">${item.value.toLocaleString()}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Last Sold:</span>
                  <span className="font-medium">{item.lastSold}</span>
                </div>
              </CardContent>
              <CardFooter className="gap-2">
                <Button size="sm" variant="outline">
                  <TrendingDown className="mr-2 h-4 w-4" />
                  Discount
                </Button>
                <Button size="sm" variant="destructive">
                  Write-off
                </Button>
              </CardFooter>
            </Card>
          ))
        )}
      </div>
    </div>
  );
}
