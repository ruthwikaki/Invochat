
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
import type { Alert } from '@/types';
import { cn } from '@/lib/utils';
import { AlertCircle, CheckCircle, Info, Bot, Settings, History, Clock, TrendingDown } from 'lucide-react';
import { useState, useEffect, useMemo } from 'react';
import { useToast } from '@/hooks/use-toast';
import { getAlertsData } from '@/app/data-actions';
import { Skeleton } from '@/components/ui/skeleton';
import { formatDistanceToNow } from 'date-fns';
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { motion } from 'framer-motion';


function AlertCard({ alert }: { alert: Alert }) {
  const [formattedDate, setFormattedDate] = useState('');

  useEffect(() => {
    setFormattedDate(formatDistanceToNow(new Date(alert.timestamp), { addSuffix: true }));
  }, [alert.timestamp]);

  const getIcon = () => {
    switch(alert.type) {
        case 'predictive': return Clock;
        case 'low_stock': return AlertCircle;
        case 'profit_warning': return TrendingDown;
        default: return Info;
    }
  }

  const getCardClass = () => {
     switch(alert.type) {
        case 'predictive': return 'border-amber-500/50 bg-amber-500/5';
        case 'low_stock': return 'border-warning/50 bg-warning/5';
        case 'profit_warning': return 'border-destructive/50 bg-destructive/5';
        default: return 'border-blue-500/50 bg-blue-500/5';
    }
  }
  
  const getIconColor = () => {
     switch(alert.type) {
        case 'predictive': return 'text-amber-500';
        case 'low_stock': return 'text-warning';
        case 'profit_warning': return 'text-destructive';
        default: return 'text-blue-500';
    }
  }
  
  const getBadgeVariant = () => {
    switch(alert.type) {
      case 'low_stock':
      case 'profit_warning':
        return 'destructive';
      case 'predictive':
        return 'default';
      default:
        return 'secondary';
    }
  }

  const Icon = getIcon();
  
  return (
    <motion.div
      initial={{ opacity: 0, y: 30 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: "easeOut" }}
    >
      <Card className={cn("transition-all duration-300 hover:shadow-xl hover:-translate-y-1", getCardClass())}>
        <CardHeader>
          <div className="flex justify-between items-start gap-4">
            <div className="flex items-start gap-4">
               <Icon className={cn("h-6 w-6 mt-1 shrink-0", getIconColor())} />
               <div>
                  <CardTitle>{alert.title}</CardTitle>
                  <CardDescription>
                    Detected {formattedDate}
                  </CardDescription>
               </div>
            </div>
            <Badge variant={getBadgeVariant()} className="capitalize shrink-0">{alert.type.replace(/_/g, ' ')}</Badge>
          </div>
        </CardHeader>
        <CardContent className="pl-14">
          <p className="mb-4">{alert.message}</p>
           <div className="text-sm bg-background/50 p-3 rounded-md space-y-2 border">
              {alert.metadata.productName && <p><strong>Product:</strong> {alert.metadata.productName}</p>}
              {alert.metadata.currentStock !== undefined && <p><strong>Stock:</strong> {alert.metadata.currentStock}</p>}
              {alert.metadata.reorderPoint !== undefined && <p><strong>Reorder Point:</strong> {alert.metadata.reorderPoint}</p>}
              {alert.metadata.daysOfStockRemaining !== undefined && <p><strong>Est. Days of Stock Remaining:</strong> {Math.round(alert.metadata.daysOfStockRemaining)}</p>}
              {alert.metadata.lastSoldDate && <p><strong>Last Sold:</strong> {new Date(alert.metadata.lastSoldDate).toLocaleDateString()}</p>}
              {alert.metadata.value !== undefined && <p><strong>Value:</strong> ${alert.metadata.value.toLocaleString()}</p>}
              {alert.metadata.recent_margin !== undefined && <p><strong>Recent Margin:</strong> {`${(alert.metadata.recent_margin * 100).toFixed(1)}%`}</p>}
              {alert.metadata.previous_margin !== undefined && <p><strong>Previous Margin:</strong> {`${(alert.metadata.previous_margin * 100).toFixed(1)}%`}</p>}
           </div>
        </CardContent>
        {alert.metadata.productId && (
            <CardFooter className="pl-14 flex justify-end">
                <Button asChild>
                    <Link href={`/inventory?query=${alert.metadata.productId}`}>View Item & Take Action</Link>
                </Button>
            </CardFooter>
        )}
      </Card>
    </motion.div>
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
    <AppPage>
      <AppPageHeader
        title="Alerts"
        description="Proactive notifications based on your business rules."
      >
        <Select value={filter} onValueChange={setFilter}>
          <SelectTrigger className="w-full md:w-[180px]">
            <SelectValue placeholder="Filter by type" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Alerts</SelectItem>
            <SelectItem value="predictive">Predictive</SelectItem>
            <SelectItem value="low_stock">Low Stock</SelectItem>
            <SelectItem value="dead_stock">Dead Stock</SelectItem>
            <SelectItem value="profit_warning">Profit Warning</SelectItem>
          </SelectContent>
        </Select>
      </AppPageHeader>

      <div className="space-y-6">
        {loading ? (
            Array.from({ length: 3 }).map((_, i) => (
                <Card key={i}>
                    <CardHeader>
                      <div className="flex items-center gap-4">
                        <Skeleton className="h-6 w-6 rounded-full" />
                        <div className="space-y-1">
                          <Skeleton className="h-5 w-48" />
                          <Skeleton className="h-4 w-32" />
                        </div>
                      </div>
                    </CardHeader>
                    <CardContent className="pl-14 space-y-2">
                        <Skeleton className="h-4 w-full" />
                        <Skeleton className="h-20 w-full" />
                    </CardContent>
                    <CardFooter className="pl-14 flex justify-end">
                       <Skeleton className="h-10 w-48" />
                    </CardFooter>
                </Card>
            ))
        ) : filteredAlerts.length > 0 ? (
          filteredAlerts.map((alert) => (
            <AlertCard key={alert.id} alert={alert} />
          ))
        ) : (
          <Card className="h-60 flex flex-col items-center justify-center text-center border-2 border-dashed">
            <motion.div
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ delay: 0.2, type: 'spring', stiffness: 200, damping: 10 }}
            >
                <div className="bg-success/10 rounded-full p-4">
                    <CheckCircle className="h-12 w-12 text-success" />
                </div>
            </motion.div>
            <h3 className="mt-4 text-lg font-semibold">All Clear!</h3>
            <p className="text-muted-foreground">You have no active alerts based on your current settings.</p>
             <Button asChild className="mt-4">
                <Link href="/settings">Configure Alerts</Link>
            </Button>
          </Card>
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
                    "Dead Stock" and "Predictive" alerts are triggered by thresholds you set. Adjust these to match your business cycle. Low stock alerts use the "reorder point" for each item.
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

    </AppPage>
  );
}
