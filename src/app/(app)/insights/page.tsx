
'use client';

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { getAnomalyInsights } from '@/app/data-actions';
import { Lightbulb, AlertTriangle, CheckCircle } from 'lucide-react';
import { useState, useEffect } from 'react';
import { Skeleton } from '@/components/ui/skeleton';
import { useToast } from '@/hooks/use-toast';

function AnomalyCard({ anomaly }: { anomaly: any }) {
  const isRevenue = anomaly.anomaly_type === 'Revenue Anomaly';
  const currentValue = isRevenue ? anomaly.daily_revenue : anomaly.daily_customers;
  const averageValue = isRevenue ? anomaly.avg_revenue : anomaly.avg_customers;
  const deviation = Math.abs(currentValue - averageValue);
  const direction = currentValue > averageValue ? 'higher' : 'lower';
  
  return (
    <Card className="border-warning/50">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-warning">
          <AlertTriangle className="h-5 w-5" />
          {anomaly.anomaly_type} on {new Date(anomaly.date).toLocaleDateString()}
        </CardTitle>
        <CardDescription>
          Detected significant deviation from the 30-day average.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        <p>
          On this day, the {isRevenue ? 'daily revenue' : 'customer count'} was{' '}
          <strong>{isRevenue ? `$${Number(currentValue).toLocaleString()}` : currentValue}</strong>, which is{' '}
          {((deviation / averageValue) * 100).toFixed(1)}% {direction} than the average of{' '}
          {isRevenue ? `$${Number(averageValue).toLocaleString(undefined, {maximumFractionDigits: 0})}` : Number(averageValue).toLocaleString(undefined, {maximumFractionDigits: 0})}.
        </p>
      </CardContent>
    </Card>
  );
}

export default function InsightsPage() {
  const [anomalies, setAnomalies] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const { toast } = useToast();

  useEffect(() => {
    async function fetchInsights() {
      try {
        setLoading(true);
        const data = await getAnomalyInsights();
        setAnomalies(data);
      } catch (error: any) {
        toast({
          variant: 'destructive',
          title: 'Error Fetching Insights',
          description: error.message || 'Could not load anomaly data.'
        });
      } finally {
        setLoading(false);
      }
    }
    fetchInsights();
  }, [toast]);

  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Proactive Insights</h1>
        </div>
      </div>
      
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Lightbulb className="h-5 w-5 text-primary" />
            Anomaly Detection
          </CardTitle>
          <CardDescription>
            The engine automatically scans your recent data for significant events or deviations from normal patterns.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {loading ? (
            <div className="space-y-4">
              <Skeleton className="h-24 w-full" />
              <Skeleton className="h-24 w-full" />
            </div>
          ) : anomalies.length > 0 ? (
            anomalies.map((anomaly, index) => (
              <AnomalyCard key={index} anomaly={anomaly} />
            ))
          ) : (
            <div className="h-40 flex flex-col items-center justify-center text-center border-2 border-dashed rounded-lg">
              <CheckCircle className="h-12 w-12 text-muted-foreground" />
              <h3 className="mt-4 text-lg font-semibold">No Anomalies Found</h3>
              <p className="text-muted-foreground">Your recent business activity appears to be within normal parameters.</p>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
