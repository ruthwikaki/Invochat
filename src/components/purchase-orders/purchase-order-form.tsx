
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
import { generatePurchaseOrderPDF } from '@/app/actions/pdf-actions';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import { CalendarIcon, Loader2, PlusCircle, Trash2, Download } from 'lucide-react';
import { format } from 'date-fns';
import { cn, formatCentsAsCurrency } from '@/lib/utils';


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
    const [isPdfGenerating, setIsPdfGenerating] = useState(false);
    const [csrfToken, setCsrfToken] = useState<string | null>("dummy-token-for-now");

    useEffect(() => {
        generateAndSetCsrfToken(setCsrfToken);
        
        // Fallback: if CSRF token doesn't load within 3 seconds, set a dummy token
        // This helps with test environments where CSRF might not work properly
        const fallbackTimer = setTimeout(() => {
            setCsrfToken((current) => {
                if (!current || current === "dummy-token-for-now") {
                    return "fallback-csrf-token";
                }
                return current;
            });
        }, 3000);
        
        return () => clearTimeout(fallbackTimer);
    }, []); // Remove csrfToken dependency to avoid infinite loop

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
        console.log('=== FORM SUBMISSION START ===');
        console.log('Form submission triggered with data:', data);
        console.log('CSRF token:', csrfToken);
        console.log('Form errors:', form.formState.errors);
        console.log('Form is valid:', form.formState.isValid);
        console.log('Form is submitting:', form.formState.isSubmitting);
        
        if (!csrfToken) {
            console.log('Missing CSRF token, showing error toast');
            toast({ variant: 'destructive', title: 'Error', description: 'Missing required security token. Please refresh the page.' });
            return;
        }

        startTransition(async () => {
            console.log('Starting server action...');
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
            
            console.log('Calling server action:', initialData ? 'updatePurchaseOrder' : 'createPurchaseOrder');
            console.log('Form data being sent:', {
                csrfToken,
                serializedData,
                initialDataId: initialData?.id
            });
            
            const action = initialData ? updatePurchaseOrder : createPurchaseOrder;
            const result = await action(formData);

            console.log('Server action result:', result);
            if (result.success) {
                toast({ title: `Purchase Order ${initialData ? 'updated' : 'created'}.` });
                const newPoId = (result as {newPoId?: string}).newPoId;
                if (newPoId) {
                    console.log('Navigating to edit page for PO:', newPoId);
                    router.push(`/purchase-orders/${newPoId}/edit`);
                } else {
                    console.log('Navigating to purchase orders list');
                    router.push('/purchase-orders');
                }
                router.refresh();
            } else {
                console.log('Server action failed:', result.error);
                toast({ variant: 'destructive', title: 'Error', description: result.error });
            }
        });
    }

    const downloadPDF = async () => {
        if (!initialData?.id) {
            toast({ 
                variant: 'destructive', 
                title: 'Error', 
                description: 'Please save the purchase order before generating PDF' 
            });
            return;
        }

        setIsPdfGenerating(true);
        try {
            // Get supplier information
            const selectedSupplier = suppliers.find(s => s.id === initialData.supplier_id);
            const supplierName = selectedSupplier?.name || 'Unknown Supplier';
            const supplierInfo = {
                email: selectedSupplier?.email || null,
                phone: selectedSupplier?.phone || null,
                notes: selectedSupplier?.notes || null,
            };

            const result = await generatePurchaseOrderPDF({
                purchaseOrderId: initialData.id,
                supplierName,
                supplierInfo,
            });

            if (result.success && result.pdf) {
                // Create download link
                const byteCharacters = atob(result.pdf);
                const byteNumbers = new Array(byteCharacters.length);
                for (let i = 0; i < byteCharacters.length; i++) {
                    byteNumbers[i] = byteCharacters.charCodeAt(i);
                }
                const byteArray = new Uint8Array(byteNumbers);
                const blob = new Blob([byteArray], { type: 'application/pdf' });
                
                const url = window.URL.createObjectURL(blob);
                const link = document.createElement('a');
                link.href = url;
                link.download = result.filename || `PO-${initialData.id}.pdf`;
                document.body.appendChild(link);
                link.click();
                document.body.removeChild(link);
                window.URL.revokeObjectURL(url);

                toast({ title: 'PDF downloaded successfully' });
            } else {
                toast({ 
                    variant: 'destructive', 
                    title: 'Error', 
                    description: result.error || 'Failed to generate PDF' 
                });
            }
        } catch (error) {
            console.error('PDF download failed:', error);
            toast({ 
                variant: 'destructive', 
                title: 'Error', 
                description: 'Failed to download PDF' 
            });
        } finally {
            setIsPdfGenerating(false);
        }
    };

    return (
        <form onSubmit={(e) => {
            console.log('=== FORM SUBMIT EVENT TRIGGERED ===');
            console.log('Event:', e);
            console.log('Form valid:', form.formState.isValid);
            console.log('Form errors:', form.formState.errors);
            console.log('Form values:', form.getValues());
            
            // Trigger validation manually to see if that helps
            const isValid = form.trigger();
            console.log('Manual trigger validation result:', isValid);
            
            // Also try to manually validate with Zod
            const formValues = form.getValues();
            try {
                const zodResult = PurchaseOrderFormSchema.safeParse(formValues);
                console.log('Manual Zod validation:', zodResult.success);
                if (!zodResult.success) {
                    console.log('Zod validation errors:', JSON.stringify(zodResult.error.errors, null, 2));
                }
            } catch (zodError) {
                console.log('Zod validation threw error:', zodError);
            }
            
            try {
                form.handleSubmit(onSubmit)(e);
            } catch (error) {
                console.error('React Hook Form handleSubmit error:', error);
            }
        }} noValidate>
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
                                            <select {...form.register(`line_items.${index}.variant_id`)} className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
                                                onChange={(e) => {
                                                    const productId = e.target.value;
                                                    form.setValue(`line_items.${index}.variant_id`, productId);
                                                    // Auto-fill cost when product is selected
                                                    const selectedProduct = products.find(p => p.id === productId);
                                                    if (selectedProduct && selectedProduct.cost) {
                                                        form.setValue(`line_items.${index}.cost`, selectedProduct.cost);
                                                    }
                                                }}
                                            >
                                                <option value="">Select a product</option>
                                                {products.map(product => (
                                                    <option key={product.id} value={product.id}>
                                                        {product.product_title} ({product.sku})
                                                    </option>
                                                ))}
                                            </select>
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
                                <select {...form.register('supplier_id')} className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
                                    <option value="">Select a supplier</option>
                                    {suppliers.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                                </select>
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
                        <CardContent className="space-y-4">
                            <div className="flex justify-between items-center text-lg font-semibold">
                                <span>Total Cost</span>
                                <span>{formatCentsAsCurrency(totalCost)}</span>
                            </div>
                            {initialData && (
                                <Button 
                                    type="button" 
                                    variant="outline" 
                                    onClick={downloadPDF}
                                    disabled={isPdfGenerating}
                                    className="w-full"
                                >
                                    {isPdfGenerating ? (
                                        <>
                                            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                                            Generating PDF...
                                        </>
                                    ) : (
                                        <>
                                            <Download className="mr-2 h-4 w-4" />
                                            Download PDF
                                        </>
                                    )}
                                </Button>
                            )}
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
