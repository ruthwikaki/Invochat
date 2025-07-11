
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useRouter } from 'next/navigation';
import { useTransition } from 'react';
import { useToast } from '@/hooks/use-toast';
import {
  SupplierFormSchema,
  type Supplier,
  type SupplierFormData,
} from '@/types';
import { createSupplier, updateSupplier } from '@/app/data-actions';
import { Card, CardContent, CardFooter, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Loader2 } from 'lucide-react';
import { Textarea } from '../ui/textarea';

interface SupplierFormProps {
  initialData?: Supplier;
}

export function SupplierForm({ initialData }: SupplierFormProps) {
  const router = useRouter();
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();
  const isEditMode = !!initialData;

  const form = useForm<SupplierFormData>({
    resolver: zodResolver(SupplierFormSchema),
    defaultValues: {
      name: initialData?.name || '',
      email: initialData?.email || '',
      phone: initialData?.phone || '',
      default_lead_time_days: initialData?.default_lead_time_days || undefined,
      notes: initialData?.notes || '',
    },
  });

  const onSubmit = (data: SupplierFormData) => {
    startTransition(async () => {
      const result = isEditMode
        ? await updateSupplier(initialData.id, data)
        : await createSupplier(data);
      
      if (result.success) {
        toast({ title: `Supplier ${isEditMode ? 'updated' : 'created'}` });
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
            <CardHeader>
                <CardTitle>{isEditMode ? 'Edit Supplier' : 'New Supplier'}</CardTitle>
                <CardDescription>
                    Fill in the contact and account details for your supplier below.
                </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div className="space-y-2">
                        <Label htmlFor="name">Supplier Name</Label>
                        <Input id="name" {...form.register('name')} placeholder="e.g., Global Supplies Inc." />
                        {form.formState.errors.name && <p className="text-sm text-destructive">{form.formState.errors.name.message}</p>}
                    </div>
                    <div className="space-y-2">
                        <Label htmlFor="email">Contact Email</Label>
                        <Input id="email" type="email" {...form.register('email')} placeholder="e.g., sales@globalsupplies.com" />
                         {form.formState.errors.email && <p className="text-sm text-destructive">{form.formState.errors.email.message}</p>}
                    </div>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div className="space-y-2">
                        <Label htmlFor="phone">Phone Number</Label>
                        <Input id="phone" {...form.register('phone')} />
                    </div>
                    <div className="space-y-2">
                        <Label htmlFor="default_lead_time_days">Default Lead Time (Days)</Label>
                        <Input id="default_lead_time_days" type="number" {...form.register('default_lead_time_days', { valueAsNumber: true })} />
                    </div>
                </div>
                 <div className="space-y-2">
                    <Label htmlFor="notes">Notes</Label>
                    <Textarea id="notes" {...form.register('notes')} placeholder="e.g., Preferred contact method is email. Responds quickly." />
                </div>
            </CardContent>
            <CardFooter>
                 <Button type="submit" disabled={isPending}>
                    {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    {isEditMode ? 'Save Changes' : 'Create Supplier'}
                </Button>
            </CardFooter>
        </Card>
    </form>
  );
}
