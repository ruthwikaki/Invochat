
'use client';

import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useTransition } from 'react';
import type { CompanySettings } from '@/types';
import { CompanySettingsSchema } from '@/types';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useToast } from '@/hooks/use-toast';
import { updateCompanySettings } from '@/app/data-actions';
import { Loader2 } from 'lucide-react';
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf-client';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

const SettingsFormSchema = CompanySettingsSchema.pick({
    dead_stock_days: true,
    fast_moving_days: true,
    overstock_multiplier: true,
    high_value_threshold: true,
    currency: true,
    timezone: true,
});

export function CompanySettingsForm({ settings }: { settings: CompanySettings }) {
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();

  const form = useForm<z.infer<typeof SettingsFormSchema>>({
    resolver: zodResolver(SettingsFormSchema),
    defaultValues: {
      ...settings,
      high_value_threshold: settings.high_value_threshold / 100 // Convert cents to dollars for display
    },
  });

  const onSubmit = (data: z.infer<typeof SettingsFormSchema>) => {
    startTransition(async () => {
        const formData = new FormData();
        const finalData = {
          ...data,
          high_value_threshold: Math.round(data.high_value_threshold * 100) // Convert back to cents
        };

        Object.entries(finalData).forEach(([key, value]) => {
            formData.append(String(key), String(value));
        });

        const csrfToken = getCookie(CSRF_FORM_NAME);
        if(csrfToken) formData.append(CSRF_FORM_NAME, csrfToken);

        const result = await updateCompanySettings(formData);
        if(result.success) {
            toast({ title: 'Settings saved successfully' });
        } else {
            toast({ variant: 'destructive', title: 'Error', description: 'Failed to save settings.' });
        }
    });
  };

  return (
    <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4 max-w-2xl">
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="space-y-1">
          <Label htmlFor="dead_stock_days">Dead Stock Period (Days)</Label>
          <Input id="dead_stock_days" type="number" {...form.register('dead_stock_days', { valueAsNumber: true })} />
          <p className="text-xs text-muted-foreground">Items unsold for this many days are considered dead stock.</p>
        </div>
        <div className="space-y-1">
          <Label htmlFor="fast_moving_days">Fast-Moving Period (Days)</Label>
          <Input id="fast_moving_days" type="number" {...form.register('fast_moving_days', { valueAsNumber: true })} />
           <p className="text-xs text-muted-foreground">The period used to calculate sales velocity for reordering.</p>
        </div>
         <div className="space-y-1">
          <Label htmlFor="overstock_multiplier">Overstock Multiplier</Label>
          <Input id="overstock_multiplier" type="number" step="0.1" {...form.register('overstock_multiplier', { valueAsNumber: true })} />
           <p className="text-xs text-muted-foreground">Multiplier for average sales to identify overstocked items.</p>
        </div>
         <div className="space-y-1">
          <Label htmlFor="high_value_threshold">High-Value Threshold ($)</Label>
          <Input id="high_value_threshold" type="number" step="0.01" {...form.register('high_value_threshold', { valueAsNumber: true })} />
           <p className="text-xs text-muted-foreground">Cost-of-goods threshold to be considered a &apos;high-value&apos; item.</p>
        </div>
        <div className="space-y-1">
            <Label htmlFor="currency">Display Currency</Label>
            <Controller
                control={form.control}
                name="currency"
                render={({ field }) => (
                    <Select onValueChange={field.onChange} defaultValue={field.value}>
                        <SelectTrigger>
                            <SelectValue placeholder="Select a currency" />
                        </SelectTrigger>
                        <SelectContent>
                            <SelectItem value="USD">USD - United States Dollar</SelectItem>
                            <SelectItem value="EUR">EUR - Euro</SelectItem>
                            <SelectItem value="GBP">GBP - British Pound</SelectItem>
                            <SelectItem value="CAD">CAD - Canadian Dollar</SelectItem>
                            <SelectItem value="AUD">AUD - Australian Dollar</SelectItem>
                        </SelectContent>
                    </Select>
                )}
            />
            <p className="text-xs text-muted-foreground">Sets the currency symbol for all financial displays.</p>
        </div>
        <div className="space-y-1">
            <Label htmlFor="timezone">Timezone</Label>
            <Controller
                control={form.control}
                name="timezone"
                render={({ field }) => (
                    <Select onValueChange={field.onChange} defaultValue={field.value}>
                        <SelectTrigger>
                            <SelectValue placeholder="Select a timezone" />
                        </SelectTrigger>
                        <SelectContent>
                            <SelectItem value="UTC">UTC</SelectItem>
                            <SelectItem value="America/New_York">America/New_York (EST)</SelectItem>
                            <SelectItem value="America/Chicago">America/Chicago (CST)</SelectItem>
                            <SelectItem value="America/Denver">America/Denver (MST)</SelectItem>
                            <SelectItem value="America/Los_Angeles">America/Los_Angeles (PST)</SelectItem>
                            <SelectItem value="Europe/London">Europe/London (GMT)</SelectItem>
                            <SelectItem value="Europe/Paris">Europe/Paris (CET)</SelectItem>
                        </SelectContent>
                    </Select>
                )}
            />
            <p className="text-xs text-muted-foreground">Sets the local timezone for your business operations.</p>
        </div>
      </div>
      <Button type="submit" disabled={isPending}>
        {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
        Save Settings
      </Button>
    </form>
  );
}
