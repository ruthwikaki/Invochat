
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useTransition } from 'react';
import { CompanySettings, CompanySettingsSchema } from '@/types';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useToast } from '@/hooks/use-toast';
import { updateCompanySettings } from '@/app/data-actions';
import { Loader2 } from 'lucide-react';
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf';

const SettingsFormSchema = CompanySettingsSchema.omit({ 
    company_id: true, 
    created_at: true, 
    updated_at: true,
    predictive_stock_days: true,
    currency: true,
    timezone: true,
    tax_rate: true,
    custom_rules: true,
    subscription_plan: true,
    subscription_status: true,
    subscription_expires_at: true,
    stripe_customer_id: true,
    stripe_subscription_id: true,
    promo_sales_lift_multiplier: true,
});

export function CompanySettingsForm({ settings }: { settings: CompanySettings }) {
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();

  const form = useForm<z.infer<typeof SettingsFormSchema>>({
    resolver: zodResolver(SettingsFormSchema),
    defaultValues: settings,
  });

  const onSubmit = (data: z.infer<typeof SettingsFormSchema>) => {
    startTransition(async () => {
        const formData = new FormData();
        Object.entries(data).forEach(([key, value]) => {
            formData.append(key, String(value));
        });
        const csrfToken = getCookie(CSRF_FORM_NAME);
        if(csrfToken) formData.append(CSRF_FORM_NAME, csrfToken);

        await updateCompanySettings(formData);
        toast({ title: 'Settings saved successfully' });
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
          <Input id="overstock_multiplier" type="number" {...form.register('overstock_multiplier', { valueAsNumber: true })} />
           <p className="text-xs text-muted-foreground">Multiplier for average sales to identify overstocked items.</p>
        </div>
         <div className="space-y-1">
          <Label htmlFor="high_value_threshold">High-Value Threshold ($)</Label>
          <Input id="high_value_threshold" type="number" {...form.register('high_value_threshold', { valueAsNumber: true })} />
           <p className="text-xs text-muted-foreground">Cost-of-goods threshold to be considered a 'high-value' item.</p>
        </div>
      </div>
      <Button type="submit" disabled={isPending}>
        {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
        Save Settings
      </Button>
    </form>
  );
}
