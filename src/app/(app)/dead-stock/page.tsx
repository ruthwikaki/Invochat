
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
import { DollarSign, Package, TrendingDown, Bot, Settings } from 'lucide-react';
import { getDeadStockData } from '@/app/data-actions';
import { DataTable } from '@/components/ai-response/data-table';
import Link from 'next/link';

function MetricCard({ title, value, icon: Icon, label }: { title: string, value: string, icon: React.ElementType, label?: string }) {
  return (
    <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
        <Icon className="h-5 w-5 text-muted-foreground" />
        </CardHeader>
        <CardContent>
        <div className="text-2xl font-bold text-foreground">{value}</div>
        {label && <p className="text-xs text-muted-foreground">{label}</p>}
        </CardContent>
    </Card>
  );
}


export default async function DeadStockPage() {
  const deadStockData = await getDeadStockData();
  const { deadStockItems, totalValue, totalUnits } = deadStockData;

  const formattedItems = deadStockItems.map(item => ({
    ...item,
    last_sale_date: item.last_sale_date ? new Date(item.last_sale_date).toLocaleDateString() : 'Never',
    total_value: `$${item.total_value.toFixed(2)}`,
  }));

  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
       <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Dead Stock Report</h1>
        </div>
      </div>
      
      <div className="grid gap-4 md:grid-cols-2">
        <MetricCard
            title="Dead Stock Value"
            value={`$${totalValue.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`}
            icon={DollarSign}
            label="Total value of unsold inventory"
        />
        <MetricCard
            title="Dead Stock Units"
            value={totalUnits.toLocaleString()}
            icon={Package}
            label="Total units of unsold items"
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><TrendingDown className="h-5 w-5" /> Dead Stock Items</CardTitle>
          <CardDescription>
            Items that have not been sold within the 'Dead Stock Threshold' defined in your settings.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {formattedItems.length > 0 ? (
            <DataTable data={formattedItems} />
          ) : (
            <p className="text-muted-foreground text-center">No dead stock items found based on your current settings.</p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
            <CardTitle>What's Next? Take Action</CardTitle>
            <CardDescription>
                Use your data to make informed decisions. Here are some next steps you can take.
            </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-6 md:grid-cols-2">
            <div className="space-y-3">
                <h4 className="font-semibold flex items-center gap-2"><Settings className="h-4 w-4 text-primary"/> Adjust Your Strategy</h4>
                <p className="text-sm text-muted-foreground">
                    Your "Dead Stock Threshold" is a key business metric. If this report isn't useful, consider adjusting it in the settings.
                </p>
                 <Button asChild variant="outline">
                    <Link href="/settings">Adjust Threshold</Link>
                </Button>
            </div>
             <div className="space-y-3">
                <h4 className="font-semibold flex items-center gap-2"><Bot className="h-4 w-4 text-primary"/> Brainstorm with AI</h4>
                <p className="text-sm text-muted-foreground">
                    Ask InvoChat to generate marketing campaigns, discount strategies, or bundling ideas to move this inventory.
                </p>
                 <Button asChild>
                    <Link href="/chat">Ask InvoChat</Link>
                </Button>
            </div>
        </CardContent>
         <CardFooter>
            <p className="text-xs text-muted-foreground">
                Future updates will include trend analysis and one-click actions like "Create Discount."
            </p>
        </CardFooter>
      </Card>
      
    </div>
  );
}
