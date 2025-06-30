
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useRouter } from 'next/navigation';
import { useTransition } from 'react';
import { useToast } from '@/hooks/use-toast';
import {
  LocationSchema,
  LocationFormSchema,
  type Location,
  type LocationFormData,
} from '@/types';
import { createLocation, updateLocation } from '@/app/data-actions';
import { Card, CardContent, CardFooter, CardHeader, CardTitle, CardDescription } from '../ui/card';
import { Button } from '../ui/button';
import { Input } from '../ui/input';
import { Label } from '../ui/label';
import { Textarea } from '../ui/textarea';
import { Checkbox } from '../ui/checkbox';
import { Loader2 } from 'lucide-react';

interface LocationFormProps {
  initialData?: Location;
}

export function LocationForm({ initialData }: LocationFormProps) {
  const router = useRouter();
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();
  const isEditMode = !!initialData;

  const form = useForm<LocationFormData>({
    resolver: zodResolver(LocationFormSchema),
    defaultValues: {
      name: initialData?.name || '',
      address: initialData?.address || '',
      is_default: initialData?.is_default || false,
    },
  });

  const onSubmit = (data: LocationFormData) => {
    startTransition(async () => {
      const result = isEditMode
        ? await updateLocation(initialData.id, data)
        : await createLocation(data);
      
      if (result.success) {
        toast({ title: `Location ${isEditMode ? 'updated' : 'created'}` });
        router.push('/locations');
        router.refresh(); // To update the list on the locations page
      } else {
        toast({ variant: 'destructive', title: 'Error', description: result.error });
      }
    });
  };

  return (
    <form onSubmit={form.handleSubmit(onSubmit)}>
        <Card>
            <CardHeader>
                <CardTitle>{isEditMode ? 'Edit Location' : 'New Location'}</CardTitle>
                <CardDescription>
                    Fill in the details for your location below.
                </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
                <div className="space-y-2">
                    <Label htmlFor="name">Location Name</Label>
                    <Input id="name" {...form.register('name')} placeholder="e.g., Main Warehouse" />
                    {form.formState.errors.name && <p className="text-sm text-destructive">{form.formState.errors.name.message}</p>}
                </div>
                <div className="space-y-2">
                    <Label htmlFor="address">Address</Label>
                    <Textarea id="address" {...form.register('address')} placeholder="e.g., 123 Supply Chain St, Anytown, USA" />
                </div>
                <div className="flex items-center space-x-2">
                    <Controller
                        name="is_default"
                        control={form.control}
                        render={({ field }) => (
                            <Checkbox
                                id="is_default"
                                checked={field.value}
                                onCheckedChange={field.onChange}
                            />
                        )}
                    />
                    <Label htmlFor="is_default">Set as default location</Label>
                </div>
            </CardContent>
            <CardFooter>
                 <Button type="submit" disabled={isPending}>
                    {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    {isEditMode ? 'Save Changes' : 'Create Location'}
                </Button>
            </CardFooter>
        </Card>
    </form>
  );
}
