
'use client';

import { useForm, useFieldArray, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { PurchaseOrderCreateSchema, PurchaseOrderUpdateSchema, type PurchaseOrder, type PurchaseOrderCreateInput, type Supplier, type PurchaseOrderUpdateInput } from '@/types';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Popover, PopoverTrigger, PopoverContent } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Textarea } from '@/components/ui/textarea';
import { cn } from '@/lib/utils';
import { format } from 'date-fns';
import { CalendarIcon, Loader2, Plus, Trash2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { createPurchaseOrder, updatePurchaseOrder } from '@/app/data-actions';

interface PurchaseOrderFormProps {
    suppliers: Supplier[];
    initialData?: PurchaseOrder | null;
}

export function PurchaseOrderForm({ suppliers, initialData }: PurchaseOrderFormProps) {
  const router = useRouter();
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();
  const isEditMode = !!initialData;
  const formSchema = isEditMode ? PurchaseOrderUpdateSchema : PurchaseOrderCreateSchema;

  const [defaultValues] = useState(() => {
    if (isEditMode && initialData) {
        return {
            ...initialData,
            order_date: new Date(initialData.order_date),
            expected_date: initialData.expected_date ? new Date(initialData.expected_date) : null,
            items: initialData.items?.map(item => ({
                sku: item.sku,
                product_name: item.product_name,
                quantity_ordered: item.quantity_ordered,
                unit_cost: item.unit_cost,
            })) || [],
        }
    }
    return {
        po_number: `PO-${Date.now()}`,
        order_date: new Date(),
        status: 'draft',
        items: [{ sku: '', product_name: '', quantity_ordered: 1, unit_cost: 0 }],
        supplier_id: '',
        notes: '',
        expected_date: null
    }
  });

  const form = useForm<PurchaseOrderCreateInput | PurchaseOrderUpdateInput>({
    resolver: zodResolver(formSchema),
    defaultValues: defaultValues as any, // Cast to any to handle both types
  });

  const { fields, append, remove } = useFieldArray({
    control: form.control,
    name: "items",
  });

  const onSubmit = (data: PurchaseOrderCreateInput | PurchaseOrderUpdateInput) => {
    startTransition(async () => {
      const result = isEditMode
        ? await updatePurchaseOrder(initialData.id, data as PurchaseOrderUpdateInput)
        : await createPurchaseOrder(data as PurchaseOrderCreateInput);

      if (result.success) {
        toast({
          title: `Purchase Order ${isEditMode ? 'Updated' : 'Created'}`,
          description: `PO #${data.po_number} has been successfully saved.`,
        });
        router.push('/purchase-orders');
      } else {
        toast({
          variant: 'destructive',
          title: `Error ${isEditMode ? 'updating' : 'creating'} Purchase Order`,
          description: result.error,
        });
      }
    });
  };
  
  const watchedItems = form.watch('items');
  const totalAmount = watchedItems.reduce((acc, item) => {
    const quantity = Number(item.quantity_ordered) || 0;
    const cost = Number(item.unit_cost) || 0;
    return acc + (quantity * cost);
  }, 0);


  return (
    <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">
           <Card>
            <CardHeader>
              <CardTitle>Purchase Order Details</CardTitle>
              <CardDescription>Select a supplier and define PO details.</CardDescription>
            </CardHeader>
            <CardContent className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="space-y-2">
                    <Label htmlFor="supplier_id">Supplier</Label>
                    <Controller
                        control={form.control}
                        name="supplier_id"
                        render={({ field }) => (
                           <Select onValueChange={field.onChange} defaultValue={field.value}>
                            <SelectTrigger id="supplier_id">
                                <SelectValue placeholder="Select a supplier" />
                            </SelectTrigger>
                            <SelectContent>
                                {suppliers.map(s => <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>)}
                            </SelectContent>
                           </Select>
                        )}
                    />
                    {form.formState.errors.supplier_id && <p className="text-sm text-destructive">{form.formState.errors.supplier_id.message}</p>}
                </div>
                <div className="space-y-2">
                    <Label htmlFor="po_number">PO Number</Label>
                    <Input id="po_number" {...form.register('po_number')} />
                     {form.formState.errors.po_number && <p className="text-sm text-destructive">{form.formState.errors.po_number.message}</p>}
                </div>
                 <div className="space-y-2">
                    <Label htmlFor="status">Status</Label>
                    <Controller
                        control={form.control}
                        name="status"
                        render={({ field }) => (
                           <Select onValueChange={field.onChange} defaultValue={field.value}>
                            <SelectTrigger id="status">
                                <SelectValue placeholder="Select a status" />
                            </SelectTrigger>
                            <SelectContent>
                                <SelectItem value="draft">Draft</SelectItem>
                                <SelectItem value="sent">Sent</SelectItem>
                                <SelectItem value="cancelled">Cancelled</SelectItem>
                            </SelectContent>
                           </Select>
                        )}
                    />
                </div>
                <div className="space-y-2">
                    <Label htmlFor="order_date">Order Date</Label>
                    <Controller
                        control={form.control}
                        name="order_date"
                        render={({ field }) => (
                           <Popover>
                            <PopoverTrigger asChild>
                                <Button variant="outline" className={cn("w-full justify-start text-left font-normal", !field.value && "text-muted-foreground")}>
                                    <CalendarIcon className="mr-2 h-4 w-4" />
                                    {field.value ? format(field.value, "PPP") : <span>Pick a date</span>}
                                </Button>
                            </PopoverTrigger>
                            <PopoverContent className="w-auto p-0">
                                <Calendar mode="single" selected={field.value} onSelect={field.onChange} initialFocus />
                            </PopoverContent>
                           </Popover>
                        )}
                    />
                </div>
                <div className="space-y-2">
                    <Label htmlFor="expected_date">Expected Date</Label>
                    <Controller
                        control={form.control}
                        name="expected_date"
                        render={({ field }) => (
                           <Popover>
                            <PopoverTrigger asChild>
                                <Button variant="outline" className={cn("w-full justify-start text-left font-normal", !field.value && "text-muted-foreground")}>
                                    <CalendarIcon className="mr-2 h-4 w-4" />
                                    {field.value ? format(field.value, "PPP") : <span>Pick a date</span>}
                                </Button>
                            </PopoverTrigger>
                            <PopoverContent className="w-auto p-0">
                                <Calendar mode="single" selected={field.value || undefined} onSelect={field.onChange} initialFocus />
                            </PopoverContent>
                           </Popover>
                        )}
                    />
                </div>
            </CardContent>
           </Card>
           
           <Card>
            <CardHeader>
                <CardTitle>Items</CardTitle>
                <CardDescription>Add products to this purchase order.</CardDescription>
            </CardHeader>
            <CardContent>
                <Table>
                    <TableHeader>
                        <TableRow>
                            <TableHead className="w-2/5">SKU</TableHead>
                            <TableHead>Quantity</TableHead>
                            <TableHead>Unit Cost</TableHead>
                            <TableHead className="text-right">Total</TableHead>
                            <TableHead className="w-12"></TableHead>
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {fields.map((field, index) => {
                             const quantity = Number(form.watch(`items.${index}.quantity_ordered`)) || 0;
                             const cost = Number(form.watch(`items.${index}.unit_cost`)) || 0;
                             const lineTotal = quantity * cost;
                            return (
                            <TableRow key={field.id}>
                                <TableCell>
                                    <Input {...form.register(`items.${index}.sku`)} placeholder="Enter product SKU" />
                                </TableCell>
                                <TableCell>
                                    <Input type="number" {...form.register(`items.${index}.quantity_ordered`)} placeholder="0" />
                                </TableCell>
                                <TableCell>
                                    <Input type="number" step="0.01" {...form.register(`items.${index}.unit_cost`)} placeholder="0.00" />
                                </TableCell>
                                <TableCell className="text-right font-medium">${lineTotal.toFixed(2)}</TableCell>
                                <TableCell>
                                    <Button type="button" variant="ghost" size="icon" onClick={() => remove(index)} disabled={fields.length <= 1}>
                                        <Trash2 className="h-4 w-4 text-destructive"/>
                                    </Button>
                                </TableCell>
                            </TableRow>
                        )})}
                    </TableBody>
                </Table>
                {form.formState.errors.items && <p className="text-sm text-destructive mt-2">{form.formState.errors.items.message || form.formState.errors.items.root?.message}</p>}
                <Button type="button" variant="outline" size="sm" className="mt-4" onClick={() => append({ sku: '', product_name: '', quantity_ordered: 1, unit_cost: 0 })}>
                    <Plus className="mr-2 h-4 w-4" /> Add Item
                </Button>
            </CardContent>
           </Card>
        </div>

        <div className="lg:col-span-1">
            <Card className="sticky top-6">
                <CardHeader>
                    <CardTitle>Summary</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                     <div className="flex justify-between items-center text-lg font-semibold">
                        <span>Total Amount</span>
                        <span>${totalAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span>
                     </div>
                     <div className="space-y-2">
                        <Label htmlFor="notes">Notes</Label>
                        <Textarea id="notes" {...form.register('notes')} placeholder="Add any internal notes for this PO..." />
                     </div>
                </CardContent>
                 <CardContent>
                    <Button type="submit" size="lg" className="w-full" disabled={isPending}>
                        {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                        Save Purchase Order
                    </Button>
                 </CardContent>
            </Card>
        </div>
      </div>
    </form>
  );
}
