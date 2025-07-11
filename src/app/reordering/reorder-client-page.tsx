

'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import type { ReorderSuggestion } from '@/types';
import { useToast } from '@/hooks/use-toast';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Checkbox } from '@/components/ui/checkbox';
import { Button } from '@/components/ui/button';
import { Loader2, RefreshCw, ShoppingCart, AlertTriangle, BrainCircuit, Download } from 'lucide-react';
import { AnimatePresence, motion } from 'framer-motion';
import { TooltipProvider, Tooltip, TooltipTrigger, TooltipContent } from '../ui/tooltip';
import { cn } from '@/lib/utils';
import { Badge } from '../ui/badge';
import Papa from 'papaparse';

function AiReasoning({ suggestion }: { suggestion: ReorderSuggestion }) {
    if (!suggestion.adjustment_reason) {
        return <span className="text-muted-foreground">—</span>;
    }

    const confidence = suggestion.confidence ?? 0;
    const confidenceColor = confidence > 0.7 
        ? 'text-success' 
        : confidence > 0.4 
        ? 'text-amber-500' 
        : 'text-destructive';

    const confidenceIcon = confidence < 0.4 
        ? <AlertTriangle className="h-4 w-4 mr-1 text-destructive" /> 
        : <BrainCircuit className="h-4 w-4" />;

    return (
         <TooltipProvider>
            <Tooltip>
                <TooltipTrigger asChild>
                    <span className="flex items-center gap-1 cursor-help text-primary">
                        {confidenceIcon}
                        AI Adjusted
                    </span>
                </TooltipTrigger>
                <TooltipContent className="max-w-xs text-sm">
                    <p className="font-semibold">AI Analysis:</p>
                    <p className="mb-2">{suggestion.adjustment_reason}</p>
                    {suggestion.confidence && (
                         <p className="text-xs"><strong className={cn(confidenceColor)}>Confidence:</strong> {(suggestion.confidence * 100).toFixed(0)}%</p>
                    )}
                    {suggestion.seasonality_factor && (
                         <p className="text-xs"><strong>Seasonality Factor:</strong> {suggestion.seasonality_factor.toFixed(2)}x</p>
                    )}
                </TooltipContent>
            </Tooltip>
        </TooltipProvider>
    )
}

export function ReorderClientPage({ initialSuggestions }: { initialSuggestions: ReorderSuggestion[] }) {
  const router = useRouter();
  const { toast } = useToast();
  const [selectedSuggestions, setSelectedSuggestions] = useState<ReorderSuggestion[]>(initialSuggestions);

  const handleSelect = (suggestion: ReorderSuggestion, checked: boolean) => {
    setSelectedSuggestions(prev => 
      checked ? [...prev, suggestion] : prev.filter(s => s.sku !== suggestion.sku)
    );
  };

  const handleSelectAll = (checked: boolean) => {
    setSelectedSuggestions(checked ? initialSuggestions : []);
  };
  
  const handleExport = () => {
    if (selectedSuggestions.length === 0) {
      toast({ variant: 'destructive', title: 'No items selected', description: 'Please select items to export.' });
      return;
    }

    const dataToExport = selectedSuggestions.map(s => ({
      SKU: s.sku,
      ProductName: s.product_name,
      Supplier: s.supplier_name,
      QuantityToOrder: s.suggested_reorder_quantity,
      UnitCost: s.unit_cost ? (s.unit_cost / 100).toFixed(2) : 'N/A',
      TotalCost: s.unit_cost ? ((s.suggested_reorder_quantity * s.unit_cost) / 100).toFixed(2) : 'N/A'
    }));

    const csv = Papa.unparse(dataToExport);
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', `reorder-report-${new Date().toISOString().split('T')[0]}.csv`);
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    toast({ title: 'Export Complete', description: 'Your reorder report has been downloaded.' });
  };
  
  const isAllSelected = initialSuggestions.length > 0 && selectedSuggestions.length === initialSuggestions.length;
  const isSomeSelected = selectedSuggestions.length > 0 && selectedSuggestions.length < initialSuggestions.length;
  
  if (initialSuggestions.length === 0) {
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
    )
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>AI-Enhanced Reorder Suggestions</CardTitle>
          <CardDescription>Select items to export for your purchasing team. The AI has adjusted quantities based on historical sales data and seasonality.</CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <div className="max-h-[65vh] overflow-auto">
            <Table>
              <TableHeader className="sticky top-0 z-10 bg-background/80 backdrop-blur-sm">
                <TableRow>
                  <TableHead className="w-12">
                    <Checkbox
                        checked={isAllSelected ? true : (isSomeSelected ? 'indeterminate' : false)}
                        onCheckedChange={handleSelectAll}
                    />
                  </TableHead>
                  <TableHead>Product</TableHead>
                  <TableHead>Supplier</TableHead>
                  <TableHead className="text-right">Current Qty</TableHead>
                  <TableHead className="text-right">Base Qty</TableHead>
                  <TableHead className="text-right">AI Adjusted Qty</TableHead>
                  <TableHead>Reasoning</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {initialSuggestions.map(suggestion => (
                  <TableRow key={suggestion.sku} data-state={selectedSuggestions.some(s => s.sku === suggestion.sku) ? 'selected' : ''}>
                    <TableCell>
                      <Checkbox
                        checked={selectedSuggestions.some(s => s.sku === suggestion.sku)}
                        onCheckedChange={(checked) => handleSelect(suggestion, !!checked)}
                      />
                    </TableCell>
                    <TableCell>
                        <div className="font-medium">{suggestion.product_name}</div>
                        <div className="text-xs text-muted-foreground">{suggestion.sku}</div>
                    </TableCell>
                    <TableCell>{suggestion.supplier_name}</TableCell>
                    <TableCell className="text-right">{suggestion.current_quantity}</TableCell>
                    <TableCell className="text-right text-muted-foreground">{suggestion.base_quantity}</TableCell>
                    <TableCell className="text-right font-bold text-primary">{suggestion.suggested_reorder_quantity}</TableCell>
                    <TableCell>
                        <AiReasoning suggestion={suggestion} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
      
       <AnimatePresence>
            {selectedSuggestions.length > 0 && (
                <motion.div
                    initial={{ y: 100, opacity: 0 }}
                    animate={{ y: 0, opacity: 1 }}
                    exit={{ y: 100, opacity: 0 }}
                    transition={{ type: 'spring', stiffness: 300, damping: 30 }}
                    className="fixed bottom-4 left-1/2 -translate-x-1/2 w-auto"
                >
                    <div className="flex items-center gap-4 bg-background/80 backdrop-blur-lg border rounded-full p-2 pl-4 shadow-2xl">
                        <p className="text-sm font-medium">{selectedSuggestions.length} item(s) selected</p>
                        <Button onClick={handleExport}>
                             <Download className="mr-2 h-4 w-4" /> Export Selected to CSV
                        </Button>
                    </div>
                </motion.div>
            )}
        </AnimatePresence>
    </div>
  );
}
