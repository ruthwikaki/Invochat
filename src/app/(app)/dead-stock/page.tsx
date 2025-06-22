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
import { mockDeadStock } from '@/lib/mock-data';
import { DollarSign, Package, TrendingDown } from 'lucide-react';

export default function DeadStockPage() {
  const totalDeadStockValue = mockDeadStock.reduce(
    (acc, item) => acc + item.value,
    0
  );

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
            <div className="text-3xl font-bold">${totalDeadStockValue.toLocaleString()}</div>
            <p className="text-xs">Across {mockDeadStock.length} items</p>
        </CardContent>
      </Card>

      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        {mockDeadStock.map((item) => (
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
        ))}
      </div>
    </div>
  );
}
