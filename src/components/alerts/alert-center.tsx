
'use client';

import { useState, useEffect } from 'react';
import { Bell, X, Check, AlertTriangle, Info, AlertCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import type { Alert as AlertType } from '@/types';
import { useAuth } from '@/context/auth-context';
import { Skeleton } from '../ui/skeleton';
import { motion, AnimatePresence } from 'framer-motion';

export function AlertCenter() {
  const { user } = useAuth();
  const [alerts, setAlerts] = useState<AlertType[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (user?.app_metadata.company_id) {
      fetchAlerts();
      const interval = setInterval(fetchAlerts, 60000); // Poll every minute
      return () => clearInterval(interval);
    }
  }, [user]);

  const fetchAlerts = async () => {
    try {
      const response = await fetch(`/api/alerts`);
      const data = await response.json();
      if (response.ok) {
        setAlerts(data.alerts || []);
      }
    } catch (error) {
      console.error('Failed to fetch alerts:', error);
    } finally {
      setLoading(false);
    }
  };

  const markAsRead = async (alertId: string) => {
    try {
      setAlerts(prev => prev.map(alert => alert.id === alertId ? { ...alert, read: true } : alert));
      await fetch('/api/alerts/read', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ alertId })
      });
    } catch (error) {
      console.error('Failed to mark alert as read:', error);
    }
  };

  const dismissAlert = async (alertId: string) => {
    const originalAlerts = alerts;
    setAlerts(prev => prev.filter(alert => alert.id !== alertId));
    try {
      await fetch('/api/alerts/dismiss', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ alertId })
      });
    } catch (error) {
      console.error('Failed to dismiss alert:', error);
      setAlerts(originalAlerts); // Revert on failure
    }
  };

  const getSeverityIcon = (severity: string) => {
    switch (severity) {
      case 'critical': return <AlertCircle className="h-4 w-4 text-red-500" />;
      case 'warning': return <AlertTriangle className="h-4 w-4 text-yellow-500" />;
      default: return <Info className="h-4 w-4 text-blue-500" />;
    }
  };
  
  const unreadCount = alerts.filter(a => !a.read).length;

  return (
    <Popover open={isOpen} onOpenChange={setIsOpen}>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon" className="relative h-8 w-8">
          <Bell className="h-4 w-4" />
          <AnimatePresence>
          {unreadCount > 0 && (
            <motion.div
                initial={{ scale: 0, opacity: 0}}
                animate={{ scale: 1, opacity: 1 }}
                exit={{ scale: 0, opacity: 0 }}
                className="absolute -top-1 -right-1 flex h-5 w-5 items-center justify-center rounded-full bg-destructive text-destructive-foreground text-xs font-bold"
            >
              {unreadCount > 9 ? '9+' : unreadCount}
            </motion.div>
          )}
          </AnimatePresence>
        </Button>
      </PopoverTrigger>
      
      <PopoverContent className="w-80 p-0" align="end">
        <Card className="border-0 shadow-none">
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium">Notifications</CardTitle>
            <CardDescription className="text-xs">You have {unreadCount} unread alerts.</CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            {loading ? (
                 <div className="p-4 space-y-3">
                    <Skeleton className="h-16 w-full" />
                    <Skeleton className="h-16 w-full" />
                    <Skeleton className="h-16 w-full" />
                 </div>
            ) : alerts.length === 0 ? (
              <div className="p-4 text-center text-sm text-muted-foreground">
                All caught up!
              </div>
            ) : (
              <ScrollArea className="h-80">
                <div className="space-y-2 p-4">
                  {alerts.map((alert) => (
                    <div
                      key={alert.id}
                      className={`relative rounded-lg border p-3 space-y-2 transition-colors ${
                        !alert.read ? 'bg-accent/40' : 'bg-transparent'
                      }`}
                    >
                      <div className="flex items-start justify-between">
                        <div className="flex items-center gap-2">
                          {getSeverityIcon(alert.severity)}
                          <span className="text-sm font-medium">
                            {alert.title}
                          </span>
                        </div>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => dismissAlert(alert.id)}
                          className="absolute top-1 right-1 h-6 w-6 p-0"
                        >
                          <X className="h-3 w-3" />
                        </Button>
                      </div>
                      
                      <p className="text-xs text-muted-foreground">
                        {alert.message}
                      </p>
                      
                      {!alert.read && (
                          <Button
                            variant="link"
                            size="sm"
                            onClick={() => markAsRead(alert.id)}
                            className="h-6 p-0 text-xs"
                          >
                            <Check className="h-3 w-3 mr-1" />
                            Mark as read
                          </Button>
                        )}
                    </div>
                  ))}
                </div>
              </ScrollArea>
            )}
          </CardContent>
        </Card>
      </PopoverContent>
    </Popover>
  );
}
