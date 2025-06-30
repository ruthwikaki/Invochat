
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
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Loader2 } from 'lucide-react';

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
      vendor_name: initialData?.vendor_name || '',
      contact_info: initialData?.contact_info || '',
      address: initialData?.address || '',
      terms: initialData?.terms || '',
      account_number: initialData?.account_number || '',
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
            </CardHeader>
            <CardContent className="space-y-6">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div className="space-y-2">
                        <Label htmlFor="vendor_name">Supplier Name</Label>
                        <Input id="vendor_name" {...form.register('vendor_name')} placeholder="e.g., Global Supplies Inc." />
                        {form.formState.errors.vendor_name && <p className="text-sm text-destructive">{form.formState.errors.vendor_name.message}</p>}
                    </div>
                    <div className="space-y-2">
                        <Label htmlFor="contact_info">Contact Email</Label>
                        <Input id="contact_info" type="email" {...form.register('contact_info')} placeholder="e.g., sales@globalsupplies.com" />
                         {form.formState.errors.contact_info && <p className="text-sm text-destructive">{form.formState.errors.contact_info.message}</p>}
                    </div>
                </div>
                 <div className="space-y-2">
                    <Label htmlFor="address">Address</Label>
                    <Input id="address" {...form.register('address')} placeholder="e.g., 123 Industrial Way, Commerce City" />
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div className="space-y-2">
                        <Label htmlFor="terms">Payment Terms</Label>
                        <Input id="terms" {...form.register('terms')} placeholder="e.g., Net 30" />
                    </div>
                    <div className="space-y-2">
                        <Label htmlFor="account_number">Account Number</Label>
                        <Input id="account_number" {...form.register('account_number')} />
                    </div>
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
