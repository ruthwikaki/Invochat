
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
import { DollarSign, Package, TrendingDown, Clock, Bot } from 'lucide-react';
import { getDeadStockData } from '@/app/data-actions';
import { format, parseISO } from 'date-fns';
import Link from 'next/link';

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
      
      <Card>
        <CardHeader>
            <CardTitle>AI-Powered Analysis</CardTitle>
            <CardDescription>
                With the new database schema, dead stock calculation is more complex. Ask the AI for a detailed, up-to-the-minute dead stock report.
            </CardDescription>
        </CardHeader>
        <CardContent>
            <p className="text-muted-foreground mb-4">Try asking questions like:</p>
            <ul className="list-disc pl-5 space-y-2 text-sm">
                <li>"Show me all products that haven't sold in the last 90 days."</li>
                <li>"What's my total dead stock value?"</li>
                <li>"Create a list of dead stock items worth over $500."</li>
            </ul>
        </CardContent>
        <CardFooter>
            <Button asChild>
                <Link href="/chat">
                    <Bot className="mr-2 h-4 w-4" />
                    Ask InvoChat
                </Link>
            </Button>
        </CardFooter>
      </Card>
      
    </div>
  );
}
