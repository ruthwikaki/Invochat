
'use client';

import type { PurchaseOrderWithSupplier } from '@/types';
import { Card, CardContent } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { formatCentsAsCurrency } from '@/lib/utils';
import { cn } from '@/lib/utils';
import { motion } from 'framer-motion';

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

  if (initialPurchaseOrders.length === 0) {
    return (
       <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
            <motion.div
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
                className="relative bg-primary/10 rounded-full p-6"
            >
                <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="h-16 w-16 text-primary"><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M12 22h-1a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h7l5 5v11a2 2 0 0 1-2 2Z"/><path d="M12 18H7.5a1.5 1.5 0 0 1 0-3h1"/><path d="m10 12-2 2 2 2"/><path d="M7 12h5"/></svg>
            </motion.div>
            <h3 className="mt-6 text-xl font-semibold">No Purchase Orders Found</h3>
            <p className="mt-2 text-muted-foreground">
                Purchase orders you create from the Reordering page will appear here.
            </p>
        </Card>
    );
  }

  return (
    <Card>
      <CardContent className="p-0">
        <div className="overflow-x-auto">
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
            {initialPurchaseOrders.map(po => (
                <TableRow key={po.id}>
                  <TableCell className="font-medium">{po.po_number}</TableCell>
                  <TableCell>{po.supplier_name || 'N/A'}</TableCell>
                  <TableCell>
                    <Badge variant="outline" className={cn("whitespace-nowrap", statusColors[po.status] || '')}>
                        {po.status}
                    </Badge>
                  </TableCell>
                  <TableCell>{format(new Date(po.created_at), 'MMM d, yyyy')}</TableCell>
                  <TableCell>{po.expected_arrival_date ? format(new Date(po.expected_arrival_date), 'MMM d, yyyy') : 'N/A'}</TableCell>
                  <TableCell className="text-right font-tabular">{formatCentsAsCurrency(po.total_cost)}</TableCell>
                </TableRow>
              ))
            }
          </TableBody>
        </Table>
        </div>
      </CardContent>
    </Card>
  );
}
