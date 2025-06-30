
'use client';

import { useForm, useFieldArray } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { type PurchaseOrder } from '@/types';
import { useRouter } from 'next/navigation';
import { useTransition } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { cn } from '@/lib/utils';
import { format } from 'date-fns';
import { Loader2, PackageCheck, Info } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { receivePurchaseOrderItems } from '@/app/data-actions';
import { Badge } from '../ui/badge';
import { Alert, AlertTitle, AlertDescription } from '../ui/alert';

const ReceiveItemsSchema = z.object({
  poId: z.string().uuid(),
  items: z.array(z.object({
    sku: z.string(),
    product_name: z.string(),
    quantity_ordered: z.number(),
    quantity_already_received: z.number(),
    quantity_to_receive: z.coerce.number().int().min(0, 'Cannot be negative.'),
  })).refine(items => items.some(item => item.quantity_to_receive > 0), {
    message: 'You must enter a quantity for at least one item to receive.',
  }),
});
type ReceiveItemsFormValues = z.infer<typeof ReceiveItemsSchema>;

export function PurchaseOrderReceiveForm({ purchaseOrder }: { purchaseOrder: PurchaseOrder }) {
  const router = useRouter();
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();

  const form = useForm<ReceiveItemsFormValues>({
    resolver: zodResolver(ReceiveItemsSchema),
    defaultValues: {
      poId: purchaseOrder.id,
      items: purchaseOrder.items?.map(item => ({
        sku: item.sku,
        product_name: item.product_name || 'Unknown Product', // Assuming product_name is available
        quantity_ordered: item.quantity_ordered,
        quantity_already_received: item.quantity_received,
        quantity_to_receive: 0,
      })) || [],
    },
  });

  const { fields } = useFieldArray({
    control: form.control,
    name: 'items',
  });

  const onSubmit = (data: ReceiveItemsFormValues) => {
    startTransition(async () => {
      const result = await receivePurchaseOrderItems(data);
      if (result.success) {
        toast({
          title: 'Items Received',
          description: `Inventory has been updated for PO #${purchaseOrder.po_number}.`,
        });
        router.refresh();
      } else {
        toast({
          variant: 'destructive',
          title: 'Error Receiving Items',
          description: result.error,
        });
      }
    });
  };

  const isFullyReceived = purchaseOrder.status === 'received';

  return (
    <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
        <Card>
            <CardHeader>
                <CardTitle>Receive Items</CardTitle>
                <CardDescription>Enter the quantity of each item you are receiving into inventory now.</CardDescription>
            </CardHeader>
            <CardContent>
                {isFullyReceived && (
                    <Alert variant="default" className="mb-4 bg-success/10 border-success/20">
                        <PackageCheck className="h-4 w-4" />
                        <AlertTitle className="text-success">Order Fully Received</AlertTitle>
                        <AlertDescription>
                            All items for this purchase order have been received and added to inventory.
                        </AlertDescription>
                    </Alert>
                )}
                <div className="max-h-[60vh] overflow-auto">
                    <Table>
                        <TableHeader className="sticky top-0 bg-background/95 backdrop-blur-sm">
                            <TableRow>
                                <TableHead>Product</TableHead>
                                <TableHead className="text-center">Ordered</TableHead>
                                <TableHead className="text-center">Received</TableHead>
                                <TableHead className="text-center">Outstanding</TableHead>
                                <TableHead className="w-48 text-center">Receiving Now</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {fields.map((field, index) => {
                                const outstanding = field.quantity_ordered - field.quantity_already_received;
                                return (
                                <TableRow key={field.id}>
                                    <TableCell>
                                        <div className="font-medium">{field.product_name}</div>
                                        <div className="text-xs text-muted-foreground">{field.sku}</div>
                                    </TableCell>
                                    <TableCell className="text-center">{field.quantity_ordered}</TableCell>
                                    <TableCell className="text-center">{field.quantity_already_received}</TableCell>
                                    <TableCell className="text-center font-semibold">{outstanding}</TableCell>
                                    <TableCell>
                                        <Input
                                            type="number"
                                            className="text-center"
                                            {...form.register(`items.${index}.quantity_to_receive`)}
                                            max={outstanding}
                                            min={0}
                                            disabled={isFullyReceived || isPending || outstanding <= 0}
                                        />
                                    </TableCell>
                                </TableRow>
                            )})}
                        </TableBody>
                    </Table>
                </div>
                 {form.formState.errors.items && (
                    <p className="text-sm text-destructive mt-4">{form.formState.errors.items.message}</p>
                 )}
            </CardContent>
            {!isFullyReceived && (
                 <CardFooter className="flex justify-end">
                    <Button type="submit" size="lg" disabled={isPending}>
                        {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                        Receive Selected Items
                    </Button>
                 </CardFooter>
            )}
        </Card>
    </form>
  );
}
