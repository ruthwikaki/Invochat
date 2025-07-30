
'use client';

import { useState, useEffect, useTransition } from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import type { AlertSettings as AlertSettingsType } from '@/services/alert-service';
import { Loader2 } from 'lucide-react';
import { Skeleton } from '../ui/skeleton';

export function AlertSettings() {
  const [settings, setSettings] = useState<AlertSettingsType | null>(null);
  const [isLoading, startLoadingTransition] = useTransition();
  const [isSaving, startSavingTransition] = useTransition();
  const { toast } = useToast();

  useEffect(() => {
    startLoadingTransition(async () => {
        try {
            const response = await fetch(`/api/alerts/settings`);
            if (response.ok) {
                const data = await response.json();
                setSettings(data.settings);
            } else {
                 toast({ title: 'Error', description: 'Failed to fetch alert settings.', variant: 'destructive' });
            }
        } catch (error) {
            toast({ title: 'Error', description: 'Failed to fetch alert settings.', variant: 'destructive' });
        }
    });
  }, []);

  const handleSettingChange = <K extends keyof AlertSettingsType>(key: K, value: AlertSettingsType[K]) => {
      if (settings) {
          setSettings({ ...settings, [key]: value });
      }
  }

  const saveSettings = () => {
    if (!settings) return;
    startSavingTransition(async () => {
      try {
        const response = await fetch('/api/alerts/settings', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ settings })
        });
        
        if (response.ok) {
          toast({ title: 'Settings saved', description: 'Alert preferences have been updated.' });
        } else {
          throw new Error('Failed to save settings');
        }
      } catch (error) {
        toast({ title: 'Error', description: 'Failed to save alert settings.', variant: 'destructive' });
      }
    });
  };
  
  if (isLoading || !settings) {
      return (
          <Card>
              <CardHeader>
                <Skeleton className="h-6 w-1/2" />
                <Skeleton className="h-4 w-3/4" />
              </CardHeader>
              <CardContent className="space-y-6">
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-24 w-full" />
              </CardContent>
          </Card>
      )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Alert & Notification Settings</CardTitle>
        <CardDescription>
            Configure thresholds and delivery preferences for automated inventory alerts.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="space-y-0.5">
            <Label htmlFor="email-notifications">Email Notifications</Label>
            <p className="text-sm text-muted-foreground">
              Receive alert emails for important inventory events.
            </p>
          </div>
          <Switch
            id="email-notifications"
            checked={settings.email_notifications}
            onCheckedChange={(checked) => handleSettingChange('email_notifications', checked)}
          />
        </div>

        <div className="flex items-center justify-between">
          <div className="space-y-0.5">
            <Label htmlFor="morning-briefing">Daily Morning Briefing</Label>
            <p className="text-sm text-muted-foreground">
              Receive a daily summary of your business metrics by email.
            </p>
          </div>
          <Switch
            id="morning-briefing"
            checked={settings.morning_briefing_enabled}
            onCheckedChange={(checked) => handleSettingChange('morning_briefing_enabled', checked)}
          />
        </div>

        {settings.morning_briefing_enabled && (
          <div className="space-y-2 pl-4 border-l-2">
            <Label htmlFor="briefing-time">Briefing Time</Label>
            <Input
              id="briefing-time"
              type="time"
              value={settings.morning_briefing_time}
              onChange={(e) => handleSettingChange('morning_briefing_time', e.target.value)}
              className="w-32"
            />
          </div>
        )}

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-4 border-t">
          <div className="space-y-2">
            <Label htmlFor="low-stock">Low Stock Threshold</Label>
             <p className="text-xs text-muted-foreground">
              Trigger a 'warning' alert when stock falls to this level.
            </p>
            <Input
              id="low-stock"
              type="number"
              value={settings.low_stock_threshold}
              onChange={(e) => handleSettingChange('low_stock_threshold', Number(e.target.value))}
            />
          </div>
          
          <div className="space-y-2">
            <Label htmlFor="critical-stock">Critical Stock Threshold</Label>
            <p className="text-xs text-muted-foreground">
              Trigger a 'critical' alert when stock falls to this level.
            </p>
            <Input
              id="critical-stock"
              type="number"
              value={settings.critical_stock_threshold}
              onChange={(e) => handleSettingChange('critical_stock_threshold', Number(e.target.value))}
            />
          </div>
        </div>

        <Button onClick={saveSettings} disabled={isSaving}>
          {isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
          Save Settings
        </Button>
      </CardContent>
    </Card>
  );
}
