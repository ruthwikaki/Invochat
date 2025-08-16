
'use client';

import { useForm, useFieldArray, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { PurchaseOrderFormSchema, type PurchaseOrderFormData } from '@/types';
import type { Supplier, UnifiedInventoryItem, PurchaseOrderWithItems } from '@/types';
import { useRouter, useSearchParams } from 'next/navigation';
import { useTransition, useEffect, useMemo, useState } from 'react';
import { useToast } from '@/hooks/use-toast';
import { CSRF_FORM_NAME, generateAndSetCsrfToken } from '@/lib/csrf-client';
import { createPurchaseOrder, updatePurchaseOrder } from '@/app/data-actions';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import { CalendarIcon, Loader2, PlusCircle, Trash2 } from 'lucide-react';
import { format } from 'date-fns';
import { cn, formatCentsAsCurrency } from '@/lib/utils';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';

interface PurchaseOrderFormProps {
    initialData?: PurchaseOrderWithItems;
    suppliers: Supplier[];
    products: UnifiedInventoryItem[];
}

export function PurchaseOrderForm({ initialData, suppliers, products }: PurchaseOrderFormProps) {
    const router = useRouter();
    const searchParams = useSearchParams();
    const { toast } = useToast();
    const [isPending, startTransition] = useTransition();
    const [csrfToken, setCsrfToken] = useState<string | null>("dummy-token-for-now");

    useEffect(() => {
        generateAndSetCsrfToken(setCsrfToken);
    }, []);

    const itemsFromParams = useMemo(() => {
        const itemsJson = searchParams.get('items');
        if (itemsJson) {
            try {
                return JSON.parse(itemsJson);
            } catch {
                return [];
            }
        }
        return [];
    }, [searchParams]);

    const form = useForm<PurchaseOrderFormData>({
        resolver: zodResolver(PurchaseOrderFormSchema),
        defaultValues: initialData ? {
            ...initialData,
            supplier_id: initialData.supplier_id || '',
            expected_arrival_date: initialData.expected_arrival_date ? new Date(initialData.expected_arrival_date) : undefined
        } : {
            supplier_id: '',
            status: 'Draft',
            line_items: itemsFromParams,
            notes: ''
        },
    });

    const { fields, append, remove } = useFieldArray({
        control: form.control,
        name: "line_items"
    });
    const lineItems = form.watch('line_items');

    useEffect(() => {
        if (itemsFromParams.length > 0 && !initialData) {
            form.setValue('line_items', itemsFromParams);
        }
    }, [itemsFromParams, form, initialData]);

    const totalCost = useMemo(() => {
        return lineItems.reduce((sum, item) => {
            const cost = item.cost || 0;
            const quantity = item.quantity || 0;
            return sum + (cost * quantity);
        }, 0);
    }, [lineItems]);

    const onSubmit = (data: PurchaseOrderFormData) => {
        if (!csrfToken) {
            toast({ variant: 'destructive', title: 'Error', description: 'Missing required security token. Please refresh the page.' });
            return;
        }

        startTransition(async () => {
            const formData = new FormData();
            formData.append(CSRF_FORM_NAME, csrfToken);

            const serializedData = {
                ...data,
                total_cost: totalCost,
                expected_arrival_date: data.expected_arrival_date?.toISOString(),
            };
            formData.append('data', JSON.stringify(serializedData));
            
            if (initialData) {
                formData.append('id', initialData.id);
            }
            
            const action = initialData ? updatePurchaseOrder : createPurchaseOrder;
            const result = await action(formData);

            if (result.success) {
                toast({ title: `Purchase Order ${initialData ? 'updated' : 'created'}.` });
                const newPoId = (result as {newPoId?: string}).newPoId;
                if (newPoId) {
                    router.push(`/purchase-orders/${newPoId}/edit`);
                } else {
                    router.push('/purchase-orders');
                }
                router.refresh();
            } else {
                toast({ variant: 'destructive', title: 'Error', description: result.error });
            }
        });
    }

    return (
        <form onSubmit={form.handleSubmit(onSubmit)}>
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                <div className="lg:col-span-2 space-y-6">
                    <Card>
                        <CardHeader>
                            <CardTitle>Line Items</CardTitle>
                            <CardDescription>Add the products you want to order.</CardDescription>
                        </CardHeader>
                        <CardContent>
                             <div className="space-y-4">
                                {fields.map((field, index) => (
                                    <div key={field.id} className="flex items-end gap-2">
                                        <div className="flex-1">
                                            <Label>Product</Label>
                                            <Controller
                                                control={form.control}
                                                name={`line_items.${index}.variant_id`}
                                                render={({ field }) => (
                                                     <Popover>
                                                        <PopoverTrigger asChild>
                                                            <Button variant="outline" className="w-full justify-start text-left font-normal">
                                                                {field.value ? products.find(p => p.id === field.value)?.product_title : "Select a product"}
                                                            </Button>
                                                        </PopoverTrigger>
                                                        <PopoverContent className="w-auto p-0" align="start">
                                                            <Command>
                                                                <CommandInput placeholder="Search products..." />
                                                                <CommandList>
                                                                    <CommandEmpty>No results found.</CommandEmpty>
                                                                    <CommandGroup>
                                                                        {products.map(product => (
                                                                            <CommandItem
                                                                                key={product.id}
                                                                                value={`${product.product_title} ${product.sku}`}
                                                                                onSelect={() => {
                                                                                    form.setValue(`line_items.${index}.variant_id`, product.id);
                                                                                    form.setValue(`line_items.${index}.cost`, product.cost || 0);
                                                                                }}
                                                                            >
                                                                                {product.product_title} ({product.sku})
                                                                            </CommandItem>
                                                                        ))}
                                                                    </CommandGroup>
                                                                </CommandList>
                                                            </Command>
                                                        </PopoverContent>
                                                    </Popover>
                                                )}
                                            />
                                        </div>
                                        <div className="w-24">
                                            <Label>Quantity</Label>
                                            <Input type="number" {...form.register(`line_items.${index}.quantity`, { valueAsNumber: true })} />
                                        </div>
                                         <div className="w-24">
                                            <Label>Unit Cost</Label>
                                            <Input type="number" {...form.register(`line_items.${index}.cost`, { valueAsNumber: true })} />
                                        </div>
                                        <Button type="button" variant="ghost" size="icon" onClick={() => remove(index)}>
                                            <Trash2 className="h-4 w-4" />
                                        </Button>
                                    </div>
                                ))}
                                <Button type="button" variant="outline" onClick={() => append({ variant_id: '', quantity: 1, cost: 0 })}>
                                    <PlusCircle className="mr-2 h-4 w-4"/> Add Item
                                </Button>
                            </div>
                        </CardContent>
                    </Card>
                </div>
                <div className="lg:col-span-1 space-y-6">
                    <Card>
                        <CardHeader>
                            <CardTitle>Details</CardTitle>
                        </CardHeader>
                        <CardContent className="space-y-4">
                             <div className="space-y-2">
                                <Label htmlFor="supplier_id">Supplier</Label>
                                <Controller
                                    control={form.control}
                                    name="supplier_id"
                                    render={({ field }) => (
                                        <Select onValueChange={field.onChange} defaultValue={field.value} required>
                                            <SelectTrigger><SelectValue placeholder="Select a supplier" /></SelectTrigger>
                                            <SelectContent>
                                                {suppliers.map(s => <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>)}
                                            </SelectContent>
                                        </Select>
                                    )}
                                />
                                <Button variant="link" size="sm" className="p-0 h-auto" type="button" onClick={() => router.push('/suppliers/new')}>Create new supplier</Button>
                            </div>
                             <div className="space-y-2">
                                <Label htmlFor="status">Status</Label>
                                 <Controller
                                    control={form.control}
                                    name="status"
                                    render={({ field }) => (
                                        <Select onValueChange={field.onChange} defaultValue={field.value}>
                                            <SelectTrigger><SelectValue /></SelectTrigger>
                                            <SelectContent>
                                                <SelectItem value="Draft">Draft</SelectItem>
                                                <SelectItem value="Ordered">Ordered</SelectItem>
                                                <SelectItem value="Partially Received">Partially Received</SelectItem>
                                                <SelectItem value="Received">Received</SelectItem>
                                                <SelectItem value="Cancelled">Cancelled</SelectItem>
                                            </SelectContent>
                                        </Select>
                                    )}
                                />
                            </div>
                            <div className="space-y-2">
                               <Label>Expected Arrival Date</Label>
                               <Controller
                                    control={form.control}
                                    name="expected_arrival_date"
                                    render={({ field }) => (
                                         <Popover>
                                            <PopoverTrigger asChild>
                                            <Button
                                                variant={"outline"}
                                                className={cn("w-full justify-start text-left font-normal", !field.value && "text-muted-foreground")}
                                            >
                                                <CalendarIcon className="mr-2 h-4 w-4" />
                                                {field.value ? format(field.value, "PPP") : <span>Pick a date</span>}
                                            </Button>
                                            </PopoverTrigger>
                                            <PopoverContent className="w-auto p-0">
                                            <Calendar
                                                mode="single"
                                                selected={field.value}
                                                onSelect={field.onChange}
                                                initialFocus
                                            />
                                            </PopoverContent>
                                        </Popover>
                                    )}
                               />
                            </div>
                              <div className="space-y-2">
                                <Label htmlFor="notes">Notes</Label>
                                <Textarea id="notes" {...form.register('notes')} />
                            </div>
                        </CardContent>
                    </Card>
                     <Card>
                        <CardHeader>
                            <CardTitle>Summary</CardTitle>
                        </CardHeader>
                        <CardContent>
                            <div className="flex justify-between items-center text-lg font-semibold">
                                <span>Total Cost</span>
                                <span>{formatCentsAsCurrency(totalCost)}</span>
                            </div>
                        </CardContent>
                    </Card>
                    <div className="flex justify-end gap-2">
                        <Button type="button" variant="outline" onClick={() => router.back()}>Cancel</Button>
                        <Button type="submit" disabled={isPending || !csrfToken}>
                            {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                            {initialData ? 'Save Changes' : 'Create Purchase Order'}
                        </Button>
                    </div>
                </div>
            </div>
        </form>
    );
}
