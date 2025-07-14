
'use client';

import type { PurchaseOrderWithSupplier } from '@/types';
import { Card, CardContent } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { formatCentsAsCurrency } from '@/lib/utils';
import { cn } from '@/lib/utils';

interface PurchaseOrdersClientPageProps {
  initialPurchaseOrders: PurchaseOrderWithSupplier[];
}

const statusColors: { [key: string]: string } = {
    'Draft': 'bg-gray-500/10 text-gray-600 dark:text-gray-400 border-gray-500/20',
    'Ordered': 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/20',
    'Partially Received': 'bg-amber-500/10 text-amber-600 dark:text-amber-400 border-amber-500/20',
    'Received': 'bg-green-500/10 text-green-600 dark:text-green-400 border-green-500/20',
    'Cancelled': 'bg-red-500/10 text-red-600 dark:text-red-400 border-red-500/20',
};

export function PurchaseOrdersClientPage({ initialPurchaseOrders }: PurchaseOrdersClientPageProps) {

  return (
    <Card>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>PO Number</TableHead>
              <TableHead>Supplier</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Created Date</TableHead>
              <TableHead>Expected Arrival</TableHead>
              <TableHead className="text-right">Total Cost</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {initialPurchaseOrders.length === 0 ? (
              <TableRow>
                <TableCell colSpan={6} className="h-24 text-center">
                  No purchase orders found.
                </TableCell>
              </TableRow>
            ) : (
                initialPurchaseOrders.map(po => (
                <TableRow key={po.id}>
                  <TableCell className="font-medium">{po.po_number}</TableCell>
                  <TableCell>{po.supplier_name || 'N/A'}</TableCell>
                  <TableCell>
                    <Badge variant="outline" className={cn(statusColors[po.status] || '')}>
                        {po.status}
                    </Badge>
                  </TableCell>
                  <TableCell>{format(new Date(po.created_at), 'MMM d, yyyy')}</TableCell>
                  <TableCell>{po.expected_arrival_date ? format(new Date(po.expected_arrival_date), 'MMM d, yyyy') : 'N/A'}</TableCell>
                  <TableCell className="text-right">{formatCentsAsCurrency(po.total_cost)}</TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
