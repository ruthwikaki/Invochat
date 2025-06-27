
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
import { DollarSign, Package, TrendingDown, Clock } from 'lucide-react';
import { getDeadStockData } from '@/app/data-actions';
import { format, parseISO } from 'date-fns';

export default async function DeadStockPage() {
  const deadStockData = await getDeadStockData();
  const { deadStock, totalValue, totalUnits, averageAge } = deadStockData;

  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
       <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Dead Stock</h1>
        </div>
      </div>
      
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="border-destructive/50 text-destructive">
            <CardHeader className="flex flex-row items-center justify-between pb-2">
                <CardTitle className="text-sm font-medium">Total Value</CardTitle>
                <DollarSign className="h-4 w-4 text-destructive" />
            </CardHeader>
            <CardContent>
                <div className="text-2xl font-bold">${totalValue.toLocaleString()}</div>
            </CardContent>
        </Card>
         <Card>
            <CardHeader className="flex flex-row items-center justify-between pb-2">
                <CardTitle className="text-sm font-medium">Total Units</CardTitle>
                <Package className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
                <div className="text-2xl font-bold">{totalUnits.toLocaleString()}</div>
            </CardContent>
        </Card>
        <Card>
            <CardHeader className="flex flex-row items-center justify-between pb-2">
                <CardTitle className="text-sm font-medium">Average Age</CardTitle>
                <Clock className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
                <div className="text-2xl font-bold">{averageAge} days</div>
            </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        {deadStock.length === 0 ? (
          <p className="md:col-span-2 lg:col-span-3 text-center text-muted-foreground">No dead stock items found. Great job!</p>
        ) : (
          deadStock.map((item) => (
            <Card key={item.id}>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Package className="h-5 w-5" />
                  {item.name}
                </CardTitle>
                <CardDescription>SKU: {item.sku}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-2">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Quantity:</span>
                  <span className="font-medium">{item.quantity}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Value:</span>
                  <span className="font-medium">${(item.quantity * Number(item.cost)).toLocaleString()}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Last Sold:</span>
                  <span className="font-medium">{item.last_sold_date ? format(parseISO(item.last_sold_date), 'yyyy-MM-dd') : 'N/A'}</span>
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
