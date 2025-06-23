'use client';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
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
import { AlertCircle, CheckCircle } from 'lucide-react';
import { useState, useEffect } from 'react';
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';
import { getAlertsData } from '@/app/data-actions';
import { Skeleton } from '@/components/ui/skeleton';

function AlertCard({ alert, onToggleResolved }: { alert: Alert; onToggleResolved: (id: string) => void }) {
  const [formattedDate, setFormattedDate] = useState('');

  useEffect(() => {
    setFormattedDate(new Date(alert.date).toLocaleDateString());
  }, [alert.date]);

  return (
    <Card className={cn(alert.resolved && 'bg-muted/50')}>
      <CardHeader>
        <div className="flex justify-between items-start">
          <div>
            <CardTitle className="flex items-center gap-2">
              <AlertCircle className="h-5 w-5" /> {alert.item}
            </CardTitle>
            <CardDescription>
              Triggered on: {formattedDate}
            </CardDescription>
          </div>
          <Badge variant={'destructive'}>{alert.type}</Badge>
        </div>
      </CardHeader>
      <CardContent>
        <p className="mb-4">{alert.message}</p>
        <Button
          size="sm"
          variant={alert.resolved ? 'secondary' : 'outline'}
          onClick={() => onToggleResolved(alert.id)}
        >
          <CheckCircle className="mr-2 h-4 w-4" />
          {alert.resolved ? 'Mark as Unresolved' : 'Mark as Resolved'}
        </Button>
      </CardContent>
    </Card>
  );
}


export default function AlertsPage() {
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [loading, setLoading] = useState(true);
  const { user, getIdToken } = useAuth();
  const { toast } = useToast();

  useEffect(() => {
    if (user) {
      const fetchData = async () => {
        setLoading(true);
        try {
          const token = await getIdToken();
          if (!token) throw new Error("Authentication failed");
          const data = await getAlertsData(token);
          setAlerts(data);
        } catch (error) {
          console.error("Failed to fetch alerts:", error);
          toast({ variant: 'destructive', title: 'Error', description: 'Could not load alerts data.' });
        } finally {
          setLoading(false);
        }
      };
      fetchData();
    }
  }, [user, getIdToken, toast]);


  const toggleResolved = (id: string) => {
    setAlerts(
      alerts.map((alert) =>
        alert.id === id ? { ...alert, resolved: !alert.resolved } : alert
      )
    );
  };

  return (
    <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
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
            <SelectItem value="low-stock">Low Stock</SelectItem>
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
            <AlertCard key={alert.id} alert={alert} onToggleResolved={toggleResolved} />
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
