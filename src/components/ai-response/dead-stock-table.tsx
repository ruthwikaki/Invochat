'use client';

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import type { DeadStockItem } from '@/types';
import { TrendingDown } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';

type DeadStockTableProps = {
  data: DeadStockItem[];
};

export function DeadStockTable({ data }: DeadStockTableProps) {
  if (!data || data.length === 0) {
    return (
      <Card>
        <CardContent className="p-4 text-center text-muted-foreground">
          No dead stock items found.
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
        <CardHeader>
            <CardTitle className="flex items-center gap-2">
                <TrendingDown className="h-5 w-5 text-destructive" />
                Dead Stock Report
            </CardTitle>
            <CardDescription>
                Products that have not sold recently and may require action.
            </CardDescription>
        </CardHeader>
        <CardContent>
            <div className="rounded-lg border max-h-96 overflow-auto">
            <Table>
                <TableHeader>
                <TableRow>
                    <TableHead>Product</TableHead>
                    <TableHead className="text-right">Quantity</TableHead>
                    <TableHead className="text-right">Total Value</TableHead>
                    <TableHead>Last Sold</TableHead>
                </TableRow>
                </TableHeader>
                <TableBody>
                {data.map((item) => (
                    <TableRow key={item.sku}>
                        <TableCell>
                            <div className="font-medium">{item.product_name}</div>
                            <div className="text-xs text-muted-foreground">{item.sku}</div>
                        </TableCell>
                        <TableCell className="text-right">{item.quantity}</TableCell>
                        <TableCell className="text-right font-medium">${item.total_value.toFixed(2)}</TableCell>
                        <TableCell>
                            {item.last_sale_date 
                                ? formatDistanceToNow(new Date(item.last_sale_date), { addSuffix: true }) 
                                : 'Never'
                            }
                        </TableCell>
                    </TableRow>
                ))}
                </TableBody>
            </Table>
            </div>
      </CardContent>
    </Card>
  );
}
