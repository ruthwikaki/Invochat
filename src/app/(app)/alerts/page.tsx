
'use client';
import { Badge } from '@/components/ui/badge';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
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
import { AlertCircle, CheckCircle, Info } from 'lucide-react';
import { useState, useEffect } from 'react';
import { useToast } from '@/hooks/use-toast';
import { getAlertsData } from '@/app/data-actions';
import { Skeleton } from '@/components/ui/skeleton';
import { formatDistanceToNow } from 'date-fns';

function AlertCard({ alert }: { alert: Alert }) {
  const [formattedDate, setFormattedDate] = useState('');

  useEffect(() => {
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
              Triggered {formattedDate}
            </CardDescription>
          </div>
          <Badge variant={badgeVariant}>{alert.type.replace('_', ' ')}</Badge>
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

  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
       <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Alerts</h1>
        </div>
        <Select disabled>
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
        ) : alerts.length > 0 ? (
          alerts.map((alert) => (
            <AlertCard key={alert.id} alert={alert} />
          ))
        ) : (
          <div className="h-60 flex flex-col items-center justify-center text-center border-2 border-dashed rounded-lg">
            <CheckCircle className="h-12 w-12 text-muted-foreground" />
            <h3 className="mt-4 text-lg font-semibold">All Clear!</h3>
            <p className="text-muted-foreground">You have no active alerts.</p>
          </div>
        )}
      </div>
    </div>
  );
}
