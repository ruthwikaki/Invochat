

'use client';

import { useForm, useFieldArray, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { SaleCreateSchema, type SaleCreateInput, type UnifiedInventoryItem } from '@/types';
import { useRouter } from 'next/navigation';
import { useTransition, useState, useEffect, useCallback } from 'react';
import { useDebouncedCallback } from 'use-debounce';
import { searchProductsForSale, recordSale } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '../ui/card';
import { Button } from '../ui/button';
import { Input } from '../ui/input';
import { Label } from '../ui/label';
import { Textarea } from '../ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '../ui/table';
import { Loader2, Plus, Trash2, Search, X } from 'lucide-react';
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf';

type ProductSearchResult = Pick<UnifiedInventoryItem, 'sku' | 'product_name' | 'price' | 'quantity' | 'product_id'>;

export function QuickSaleForm() {
  const router = useRouter();
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();
  const [csrfToken, setCsrfToken] = useState<string | null>(null);

  const [searchTerm, setSearchTerm] = useState('');
  const [searchResults, setSearchResults] = useState<ProductSearchResult[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  
  useEffect(() => {
    setCsrfToken(getCookie('csrf_token'));
  }, []);

  const form = useForm<SaleCreateInput>({
    resolver: zodResolver(SaleCreateSchema),
    defaultValues: {
      items: [],
      payment_method: 'card',
    },
  });

  const { fields, append, remove, update } = useFieldArray({
    control: form.control,
    name: "items",
    keyName: 'fieldId',
  });

  const debouncedSearch = useDebouncedCallback(async (query: string) => {
    if (query.length < 2) {
      setSearchResults([]);
      setIsSearching(false);
      return;
    }
    setIsSearching(true);
    const results = await searchProductsForSale(query);
    setSearchResults(results);
    setIsSearching(false);
  }, 300);

  const handleSearchChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setSearchTerm(e.target.value);
    debouncedSearch(e.target.value);
  };
  
  const addProductToCart = (product: ProductSearchResult) => {
    const existingItemIndex = fields.findIndex(field => field.product_id === product.product_id);
    if (existingItemIndex > -1) {
      const currentItem = fields[existingItemIndex];
      update(existingItemIndex, {
        ...currentItem,
        quantity: currentItem.quantity + 1
      });
    } else {
      append({
        product_id: product.product_id,
        quantity: 1,
        unit_price: product.price || 0,
      });
    }
    setSearchTerm('');
    setSearchResults([]);
  }

  const onSubmit = (data: SaleCreateInput) => {
    startTransition(async () => {
      const formData = new FormData();
      if (csrfToken) formData.append(CSRF_FORM_NAME, csrfToken);
      formData.append('saleData', JSON.stringify(data));
      
      const result = await recordSale(formData);
      
      if (result.success) {
        toast({ title: 'Sale Recorded', description: `Sale #${result.sale?.sale_number} has been created.` });
        router.push('/sales');
      } else {
        toast({ variant: 'destructive', title: 'Error', description: result.error });
      }
    });
  };
  
  const watchedItems = form.watch('items');
  const totalAmount = watchedItems.reduce((acc, item) => acc + (item.quantity * item.unit_price), 0);
  
  return (
    <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
        <div className="lg:col-span-2 space-y-6">
          <Card>
            <CardHeader>
              <CardTitle>Products</CardTitle>
              <CardDescription>Search for products to add to the sale.</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Search by name or SKU..."
                  value={searchTerm}
                  onChange={handleSearchChange}
                  className="pl-10"
                />
                {isSearching && <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 animate-spin" />}
                 {searchResults.length > 0 && (
                    <div className="absolute z-10 w-full mt-1 bg-background border rounded-md shadow-lg max-h-60 overflow-y-auto">
                        {searchResults.map(product => (
                            <div key={product.sku} onClick={() => addProductToCart(product)} className="p-2 hover:bg-accent cursor-pointer flex justify-between items-center">
                                <div>
                                    <p className="font-medium">{product.product_name}</p>
                                    <p className="text-xs text-muted-foreground">SKU: {product.sku} | Stock: {product.quantity}</p>
                                </div>
                                <p className="font-semibold">${(product.price || 0 / 100).toFixed(2)}</p>
                            </div>
                        ))}
                    </div>
                )}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
                <CardTitle>Cart</CardTitle>
            </CardHeader>
            <CardContent>
               <Table>
                    <TableHeader>
                        <TableRow>
                            <TableHead className="w-2/5">Product</TableHead>
                            <TableHead className="w-[100px]">Quantity</TableHead>
                            <TableHead className="w-[120px]">Unit Price</TableHead>
                            <TableHead className="text-right">Total</TableHead>
                            <TableHead className="w-12"></TableHead>
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {fields.length === 0 ? (
                            <TableRow>
                                <TableCell colSpan={5} className="text-center h-24">Cart is empty</TableCell>
                            </TableRow>
                        ) : fields.map((field, index) => {
                             const lineTotal = field.quantity * field.unit_price;
                            return (
                            <TableRow key={field.fieldId}>
                                <TableCell>{field.product_id}</TableCell>
                                <TableCell><Input type="number" {...form.register(`items.${index}.quantity`)} min={1} /></TableCell>
                                <TableCell><Input type="number" step="0.01" {...form.register(`items.${index}.unit_price`, { valueAsNumber: true })} /></TableCell>
                                <TableCell className="text-right font-medium">${(lineTotal/100).toFixed(2)}</TableCell>
                                <TableCell><Button type="button" variant="ghost" size="icon" onClick={() => remove(index)}><Trash2 className="h-4 w-4 text-destructive"/></Button></TableCell>
                            </TableRow>
                        )})}
                    </TableBody>
                </Table>
                {form.formState.errors.items && <p className="text-sm text-destructive mt-2">{form.formState.errors.items.message || form.formState.errors.items.root?.message}</p>}
            </CardContent>
          </Card>
        </div>

        <div className="lg:col-span-1">
          <Card className="sticky top-6">
            <CardHeader>
              <CardTitle>Finalize Sale</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="customer_name">Customer Name (Optional)</Label>
                <Input id="customer_name" {...form.register('customer_name')} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="customer_email">Customer Email (Optional)</Label>
                <Input id="customer_email" type="email" {...form.register('customer_email')} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="payment_method">Payment Method</Label>
                <Controller
                  name="payment_method"
                  control={form.control}
                  render={({ field }) => (
                    <Select onValueChange={field.onChange} value={field.value}>
                        <SelectTrigger><SelectValue placeholder="Select payment method" /></SelectTrigger>
                        <SelectContent>
                            <SelectItem value="card">Card</SelectItem>
                            <SelectItem value="cash">Cash</SelectItem>
                            <SelectItem value="other">Other</SelectItem>
                        </SelectContent>
                    </Select>
                  )}
                />
              </div>
               <div className="space-y-2">
                <Label htmlFor="notes">Notes</Label>
                <Textarea id="notes" {...form.register('notes')} />
              </div>
               <div className="flex justify-between items-center text-lg font-semibold border-t pt-4 mt-4">
                  <span>Total Amount</span>
                  <span>${(totalAmount/100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span>
               </div>
            </CardContent>
            <CardFooter>
              <Button type="submit" size="lg" className="w-full" disabled={isPending || fields.length === 0}>
                  {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                  Complete Sale
              </Button>
            </CardFooter>
          </Card>
        </div>
      </div>
    </form>
  )
}
