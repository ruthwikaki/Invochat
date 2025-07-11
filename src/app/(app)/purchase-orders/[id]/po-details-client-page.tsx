
'use client';

import { useState } from 'react';
import type { PurchaseOrder } from '@/types';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { format } from 'date-fns';
import { Truck, DollarSign, Calendar, Hash, FileText, CheckCircle, Package } from 'lucide-react';
import { cn, formatCentsAsCurrency } from '@/lib/utils';
import { Separator } from '@/components/ui/separator';

const getStatusColor = (status: PurchaseOrder['status']) => {
  if (!status) return 'border-gray-400 text-gray-500';
  switch (status) {
    case 'draft':
      return 'bg-gray-500/10 text-gray-500 border-gray-500/20';
    case 'pending_approval':
      return 'bg-amber-500/10 text-amber-600 border-amber-500/20';
    case 'sent':
      return 'bg-blue-500/10 text-blue-600 border-blue-500/20';
    case 'partial':
       return 'bg-yellow-500/10 text-yellow-600 border-yellow-500/20';
    case 'received':
      return 'bg-success/10 text-emerald-600 border-success/20';
    case 'cancelled':
      return 'bg-destructive/10 text-destructive border-destructive/20';
    default:
      return '';
  }
};

const InfoCard = ({ title, value, icon: Icon }: { title: string, value: string, icon: React.ElementType }) => (
    <div className="flex items-start gap-4">
        <Icon className="h-5 w-5 text-muted-foreground mt-1" />
        <div>
            <p className="text-sm text-muted-foreground">{title}</p>
            <p className="font-semibold">{value}</p>
        </div>
    </div>
);

export function PurchaseOrderDetailsClientPage({ initialPurchaseOrder }: { initialPurchaseOrder: PurchaseOrder }) {
    const [purchaseOrder, setPurchaseOrder] = useState(initialPurchaseOrder);
    
    const totalQuantity = purchaseOrder.items.reduce((sum, item) => sum + item.quantity, 0);

    return (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
            <div className="lg:col-span-2 space-y-6">
                <Card>
                    <CardHeader>
                        <CardTitle>PO Line Items</CardTitle>
                    </CardHeader>
                    <CardContent>
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead>Product</TableHead>
                                    <TableHead className="text-right">SKU</TableHead>
                                    <TableHead className="text-right">Quantity</TableHead>
                                    <TableHead className="text-right">Unit Cost</TableHead>
                                    <TableHead className="text-right">Total Cost</TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {purchaseOrder.items.map(item => (
                                    <TableRow key={item.id}>
                                        <TableCell className="font-medium">{item.product_name}</TableCell>
                                        <TableCell className="text-right">{item.sku}</TableCell>
                                        <TableCell className="text-right">{item.quantity}</TableCell>
                                        <TableCell className="text-right">{formatCentsAsCurrency(item.unit_cost)}</TableCell>
                                        <TableCell className="text-right font-semibold">{formatCentsAsCurrency(item.total_cost)}</TableCell>
                                    </TableRow>
                                ))}
                            </TableBody>
                        </Table>
                    </CardContent>
                </Card>
            </div>
            <div className="lg:col-span-1 space-y-6 sticky top-6">
                <Card>
                    <CardHeader>
                        <CardTitle>Summary</CardTitle>
                        <Badge className={cn('w-fit', getStatusColor(purchaseOrder.status))}>
                           {purchaseOrder.status ? purchaseOrder.status.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()) : 'Unknown'}
                        </Badge>
                    </CardHeader>
                    <CardContent className="space-y-4">
                        <InfoCard icon={Truck} title="Supplier" value={purchaseOrder.supplier_name} />
                        <InfoCard icon={Calendar} title="Order Date" value={format(new Date(purchaseOrder.order_date), 'PP')} />
                        <InfoCard icon={Calendar} title="Expected Date" value={purchaseOrder.expected_date ? format(new Date(purchaseOrder.expected_date), 'PP') : 'Not set'} />
                        <Separator />
                        <InfoCard icon={Hash} title="Total Items" value={`${totalQuantity} units`} />
                        <InfoCard icon={DollarSign} title="Total Cost" value={formatCentsAsCurrency(purchaseOrder.total_amount)} />
                    </CardContent>
                     <CardFooter>
                        <Button className="w-full" disabled={purchaseOrder.status !== 'sent'}>
                            <CheckCircle className="mr-2 h-4 w-4" />
                            Receive Stock
                        </Button>
                    </CardFooter>
                </Card>
                <Card>
                     <CardHeader>
                        <CardTitle className="flex items-center gap-2"><FileText className="h-4 w-4" />Notes</CardTitle>
                    </CardHeader>
                     <CardContent>
                        <p className="text-sm text-muted-foreground">{purchaseOrder.notes || 'No notes for this purchase order.'}</p>
                    </CardContent>
                </Card>
            </div>
        </div>
    )
}
