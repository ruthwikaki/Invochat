
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useRouter } from 'next/navigation';
import { useTransition, useEffect, useState } from 'react';
import { useToast } from '@/hooks/use-toast';
import { type Supplier, SupplierFormSchema } from '@/types';
import { createSupplier, updateSupplier } from '@/app/data-actions';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardFooter } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Loader2 } from 'lucide-react';
import { CSRF_FORM_NAME, generateAndSetCsrfToken } from '@/lib/csrf-client';
import { z } from 'zod';

interface SupplierFormProps {
  initialData?: Supplier;
}

export function SupplierForm({ initialData }: SupplierFormProps) {
  const router = useRouter();
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();
  const [csrfToken, setCsrfToken] = useState<string | null>(null);

  useEffect(() => {
    generateAndSetCsrfToken(setCsrfToken);
  }, []);

  const form = useForm<z.infer<typeof SupplierFormSchema>>({
    resolver: zodResolver(SupplierFormSchema),
    defaultValues: initialData || {
      name: '',
      email: '',
      phone: '',
      default_lead_time_days: undefined,
      notes: '',
    },
  });

  const onSubmit = (data: z.infer<typeof SupplierFormSchema>) => {
    startTransition(async () => {
      const formData = new FormData();
      if (csrfToken) {
          formData.append(CSRF_FORM_NAME, csrfToken);
      } else {
          toast({ variant: 'destructive', title: 'Error', description: 'Missing required security token. Please refresh the page.' });
          return;
      }
      
      // Append form data to the FormData object
      Object.entries(data).forEach(([key, value]) => {
          if (value !== null && value !== undefined) {
              formData.append(key, String(value));
          }
      });
      
      const action = initialData
        ? updateSupplier(initialData.id, formData)
        : createSupplier(formData);
      
      const result = await action;

      if (result.success) {
        toast({ title: `Supplier ${initialData ? 'updated' : 'created'} successfully` });
        router.push('/suppliers');
        router.refresh();
      } else {
        toast({ variant: 'destructive', title: 'Error', description: result.error });
      }
    });
  };

  return (
    <form onSubmit={form.handleSubmit(onSubmit)}>
      <Card>
        <CardContent className="p-6 space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="name">Supplier Name</Label>
              <Input id="name" {...form.register('name')} />
              {form.formState.errors.name && <p className="text-sm text-destructive">{form.formState.errors.name.message}</p>}
            </div>
            <div className="space-y-2">
              <Label htmlFor="email">Contact Email</Label>
              <Input id="email" type="email" {...form.register('email')} />
              {form.formState.errors.email && <p className="text-sm text-destructive">{form.formState.errors.email.message}</p>}
            </div>
            <div className="space-y-2">
              <Label htmlFor="phone">Phone Number</Label>
              <Input id="phone" {...form.register('phone')} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="default_lead_time_days">Default Lead Time (days)</Label>
              <Input id="default_lead_time_days" type="number" {...form.register('default_lead_time_days', { valueAsNumber: true })} />
            </div>
          </div>
          <div className="space-y-2">
            <Label htmlFor="notes">Notes</Label>
            <Textarea id="notes" {...form.register('notes')} />
          </div>
        </CardContent>
        <CardFooter className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={() => router.back()}>Cancel</Button>
            <Button type="submit" disabled={isPending || !csrfToken}>
                {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {initialData ? 'Save Changes' : 'Create Supplier'}
            </Button>
        </CardFooter>
      </Card>
    </form>
  );
}

    