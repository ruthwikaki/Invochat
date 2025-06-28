
'use client';
import { Badge } from '@/components/ui/badge';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  CardFooter,
} from '@/components/ui/card';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { SidebarTrigger } from '@/components/ui/sidebar';
import type { Alert } from '@/types';
import { cn } from '@/lib/utils';
import { AlertCircle, CheckCircle, Info, Bot, Settings, History } from 'lucide-react';
import { useState, useEffect, useMemo } from 'react';
import { useToast } from '@/hooks/use-toast';
import { getAlertsData } from '@/app/data-actions';
import { Skeleton } from '@/components/ui/skeleton';
import { formatDistanceToNow } from 'date-fns';
import Link from 'next/link';
import { Button } from '@/components/ui/button';


function AlertCard({ alert }: { alert: Alert }) {
  const [formattedDate, setFormattedDate] = useState('');

  useEffect(() => {
    // Alerts are generated on page load, so this will always be "just now" or similar.
    setFormattedDate(formatDistanceToNow(new Date(alert.timestamp), { addSuffix: true }));
  }, [alert.timestamp]);

  const Icon = alert.severity === 'warning' ? AlertCircle : Info;
  const cardClass = alert.severity === 'warning' ? 'border-warning/50 text-warning' : 'border-blue-500/50';
  const badgeVariant = alert.type === 'low_stock' ? 'destructive' : 'secondary';
  
  return (
    <Card className={cn(cardClass)}>
      <CardHeader>
        <div className="flex justify-between items-start">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Icon className="h-5 w-5" /> {alert.title}
            </CardTitle>
            <CardDescription>
              Detected {formattedDate}
            </CardDescription>
          </div>
          <Badge variant={badgeVariant}>{alert.type.replace(/_/g, ' ')}</Badge>
        </div>
      </CardHeader>
      <CardContent>
        <p className="mb-4">{alert.message}</p>
         <div className="text-xs bg-muted/80 p-2 rounded-md space-y-1">
            {alert.metadata.productName && <p><strong>Product:</strong> {alert.metadata.productName}</p>}
            {alert.metadata.currentStock !== undefined && <p><strong>Stock:</strong> {alert.metadata.currentStock}</p>}
            {alert.metadata.reorderPoint !== undefined && <p><strong>Reorder Point:</strong> {alert.metadata.reorderPoint}</p>}
            {alert.metadata.lastSoldDate && <p><strong>Last Sold:</strong> {new Date(alert.metadata.lastSoldDate).toLocaleDateString()}</p>}
            {alert.metadata.value !== undefined && <p><strong>Value:</strong> ${alert.metadata.value.toLocaleString()}</p>}
         </div>
      </CardContent>
    </Card>
  );
}


export default function AlertsPage() {
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all');
  const { toast } = useToast();

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true);
      try {
        const data = await getAlertsData();
        setAlerts(data);
      } catch (error) {
        console.error("Failed to fetch alerts:", error);
        toast({ variant: 'destructive', title: 'Error', description: 'Could not load alerts data.' });
      } finally {
        setLoading(false);
      }
    };
    fetchData();
  }, [toast]);
  
  const filteredAlerts = useMemo(() => {
    if (filter === 'all') {
      return alerts;
    }
    return alerts.filter(alert => alert.type === filter);
  }, [alerts, filter]);

  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
       <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
           <div>
            <h1 className="text-2xl font-semibold">Alerts</h1>
            <p className="text-sm text-muted-foreground">Proactive notifications based on your business rules.</p>
           </div>
        </div>
        <Select value={filter} onValueChange={setFilter}>
          <SelectTrigger className="w-full md:w-[180px]">
            <SelectValue placeholder="Filter by type" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Alerts</SelectItem>
            <SelectItem value="low_stock">Low Stock</SelectItem>
            <SelectItem value="dead_stock">Dead Stock</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-4">
        {loading ? (
            Array.from({ length: 3 }).map((_, i) => (
                <Card key={i}>
                    <CardHeader><Skeleton className="h-6 w-1/2" /></CardHeader>
                    <CardContent className="space-y-2">
                        <Skeleton className="h-4 w-full" />
                        <Skeleton className="h-8 w-32" />
                    </CardContent>
                </Card>
            ))
        ) : filteredAlerts.length > 0 ? (
          filteredAlerts.map((alert) => (
            <AlertCard key={alert.id} alert={alert} />
          ))
        ) : (
          <div className="h-60 flex flex-col items-center justify-center text-center border-2 border-dashed rounded-lg">
            <CheckCircle className="h-12 w-12 text-muted-foreground" />
            <h3 className="mt-4 text-lg font-semibold">All Clear!</h3>
            <p className="text-muted-foreground">You have no active alerts based on your current settings.</p>
          </div>
        )}
      </div>

      <Card>
        <CardHeader>
            <CardTitle>Understanding & Improving Your Alerts</CardTitle>
            <CardDescription>
                Alerts are dynamically generated based on your data and business logic. Here's how you can take action and what's coming next.
            </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-6 md:grid-cols-2">
            <div className="space-y-3">
                <h4 className="font-semibold flex items-center gap-2"><Settings className="h-4 w-4 text-primary"/> Configure Business Rules</h4>
                <p className="text-sm text-muted-foreground">
                    "Dead Stock" alerts are triggered by the threshold you set. Adjust this to match your business cycle. Low stock alerts use the "reorder point" for each item.
                </p>
                 <Button asChild variant="outline">
                    <Link href="/settings">Adjust Settings</Link>
                </Button>
            </div>
             <div className="space-y-3">
                <h4 className="font-semibold flex items-center gap-2"><Bot className="h-4 w-4 text-primary"/> Ask for Solutions</h4>
                <p className="text-sm text-muted-foreground">
                    Don't just see a problem, solve it. Ask InvoChat to create a promotion plan for a dead stock item or find the best supplier for a low stock item.
                </p>
                 <Button asChild>
                    <Link href="/chat">Ask InvoChat</Link>
                </Button>
            </div>
        </CardContent>
         <CardFooter>
            <div className="text-xs text-muted-foreground flex items-center gap-2">
              <History className="h-3 w-3" />
              <span>Future updates will include persistent alerts you can dismiss, alert history, and email notifications.</span>
            </div>
        </CardFooter>
      </Card>

    </div>
  );
}
