

'use client';

import { useState, useTransition } from 'react';
import type { ReorderSuggestion, CompanyInfo } from '@/types';
import { useToast } from '@/hooks/use-toast';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { RefreshCw, Download } from 'lucide-react';
import { motion } from 'framer-motion';
import { CreatePODialog } from './create-po-dialog';
import { formatCentsAsCurrency } from '@/lib/utils';
import { exportReorderSuggestions } from '@/app/data-actions';

interface ReorderClientPageProps {
  initialSuggestions: ReorderSuggestion[];
  companyName: string;
}

export function ReorderClientPage({ initialSuggestions, companyName }: ReorderClientPageProps) {
  const [suggestions] = useState(initialSuggestions);
  const [poData, setPoData] = useState<{ supplierName: string; items: ReorderSuggestion[] } | null>(null);
  const { toast } = useToast();

  const groupedBySupplier = suggestions.reduce((acc, item) => {
    const supplier = item.supplier_name || 'No Supplier';
    if (!acc[supplier]) acc[supplier] = [];
    acc[supplier].push(item);
    return acc;
  }, {} as Record<string, ReorderSuggestion[]>);
  
  const calculateTotal = (items: ReorderSuggestion[]) => {
    const totalCents = items.reduce((sum, item) => sum + (item.suggested_reorder_quantity * (item.unit_cost || 0)), 0);
    return formatCentsAsCurrency(totalCents);
  }

  const handleExport = async (itemsToExport: ReorderSuggestion[]) => {
    const result = await exportReorderSuggestions(itemsToExport);
    if (result.success && result.data) {
        const blob = new Blob([result.data], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.setAttribute('href', url);
        link.setAttribute('download', `reorder-report-${new Date().toISOString().split('T')[0]}.csv`);
        link.style.visibility = 'hidden';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        toast({ title: 'Export Complete', description: 'Your reorder report has been downloaded.' });
    } else {
        toast({ variant: 'destructive', title: 'Export Failed', description: result.error });
    }
  }

  if (suggestions.length === 0) {
    return (
      <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
        <motion.div
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
            className="relative bg-primary/10 rounded-full p-6"
        >
          <RefreshCw className="h-16 w-16 text-primary" />
        </motion.div>
        <h3 className="mt-6 text-xl font-semibold">No Reorder Suggestions</h3>
        <p className="mt-2 text-muted-foreground">
          Your inventory levels are healthy, or there isn't enough sales data to make a suggestion.
        </p>
      </Card>
    );
  }

  return (
    <>
      <CreatePODialog
        isOpen={!!poData}
        onClose={() => setPoData(null)}
        supplierName={poData?.supplierName || ''}
        items={poData?.items || []}
        companyInfo={{ name: companyName }}
      />
      <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-6">
        {Object.entries(groupedBySupplier).map(([supplierName, items]) => (
          <Card key={supplierName}>
            <CardHeader>
              <CardTitle>{supplierName}</CardTitle>
              <CardDescription>
                {items.length} items to reorder · Total: {calculateTotal(items)}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <ul className="space-y-2 text-sm">
                {items.map(item => (
                    <li key={item.sku} className="flex justify-between">
                        <span className="truncate pr-4">{item.product_name}</span>
                        <span className="font-semibold">{item.suggested_reorder_quantity} units</span>
                    </li>
                ))}
              </ul>
            </CardContent>
            <CardFooter>
              <Button 
                onClick={() => handleExport(items)}
                disabled={supplierName === 'No Supplier'}
                className="w-full"
              >
                <Download className="mr-2 h-4 w-4" />
                Export PO as CSV
              </Button>
            </CardFooter>
          </Card>
        ))}
      </div>
    </>
  );
}
