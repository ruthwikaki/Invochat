
'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import type { ReorderSuggestion } from '@/schemas/reorder';
import { useToast } from '@/hooks/use-toast';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Checkbox } from '@/components/ui/checkbox';
import { Button } from '@/components/ui/button';
import { Loader2, RefreshCw, ShoppingCart, AlertTriangle, BrainCircuit, Download, Info, Package, TrendingUp } from 'lucide-react';
import { AnimatePresence, motion } from 'framer-motion';
import { TooltipProvider, Tooltip, TooltipTrigger, TooltipContent } from '@/components/ui/tooltip';
import { cn } from '@/lib/utils';
import { exportReorderSuggestions, createPurchaseOrdersFromSuggestions } from '@/app/(app)/analytics/reordering/actions';

function AiReasoning({ suggestion }: { suggestion: ReorderSuggestion }) {
    if (!suggestion.adjustment_reason) {
        return <span className="text-muted-foreground">—</span>;
    }

    const confidence = suggestion.confidence ?? 0;
    const confidenceColor = confidence > 0.7 
        ? 'text-success' 
        : confidence > 0.4 
        ? 'text-warning' 
        : 'text-destructive';

    const confidenceIcon = confidence < 0.4 
        ? <AlertTriangle className="h-4 w-4 text-destructive" /> 
        : <BrainCircuit className="h-4 w-4 text-accent" />;

    return (
         <TooltipProvider>
            <Tooltip>
                <TooltipTrigger asChild>
                    <span className="flex items-center gap-1 cursor-help text-accent">
                        {confidenceIcon}
                        AI Adjusted
                    </span>
                </TooltipTrigger>
                <TooltipContent className="max-w-xs text-sm">
                    <div className="space-y-1 text-xs">
                        <div className="font-medium">AI Analysis:</div>
                        <div>{suggestion.adjustment_reason}</div>
                        <div>Confidence: {Math.round((suggestion.confidence ?? 0) * 100)}%</div>
                        <div>Seasonality Factor: {(suggestion.seasonality_factor ?? 1).toFixed(2)}x</div>
                    </div>
                </TooltipContent>
            </Tooltip>
        </TooltipProvider>
    )
}

function EmptyReorderState() {
    return (
        <div className="flex flex-col items-center justify-center min-h-[400px] p-8">
            <motion.div
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
                className="relative bg-primary/10 rounded-full p-8 mb-6"
            >
                <Package className="h-16 w-16 text-primary" />
            </motion.div>
            
            <motion.div
                initial={{ y: 20, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                transition={{ delay: 0.2 }}
                className="text-center space-y-4 max-w-md"
            >
                <h3 className="text-2xl font-semibold text-foreground">
                    All Good! No Reorders Needed
                </h3>
                <p className="text-muted-foreground text-lg leading-relaxed">
                    Your inventory levels are healthy right now. This could mean:
                </p>
                
                <div className="grid gap-3 mt-6 text-left">
                    <div className="flex items-start gap-3 p-3 bg-muted/50 rounded-lg">
                        <TrendingUp className="h-5 w-5 text-green-500 mt-0.5 flex-shrink-0" />
                        <div>
                            <p className="font-medium text-sm">Stock levels are optimal</p>
                            <p className="text-xs text-muted-foreground">All products are above their reorder points</p>
                        </div>
                    </div>
                    
                    <div className="flex items-start gap-3 p-3 bg-muted/50 rounded-lg">
                        <RefreshCw className="h-5 w-5 text-blue-500 mt-0.5 flex-shrink-0" />
                        <div>
                            <p className="font-medium text-sm">Data is still syncing</p>
                            <p className="text-xs text-muted-foreground">Recent integrations may need time to populate</p>
                        </div>
                    </div>
                    
                    <div className="flex items-start gap-3 p-3 bg-muted/50 rounded-lg">
                        <AlertTriangle className="h-5 w-5 text-amber-500 mt-0.5 flex-shrink-0" />
                        <div>
                            <p className="font-medium text-sm">Missing reorder points</p>
                            <p className="text-xs text-muted-foreground">Set reorder points in your inventory settings</p>
                        </div>
                    </div>
                </div>
                
                <div className="flex gap-3 justify-center mt-8">
                    <Button 
                        variant="outline" 
                        onClick={() => window.location.reload()}
                        className="flex items-center gap-2"
                    >
                        <RefreshCw className="h-4 w-4" />
                        Refresh
                    </Button>
                    <Button 
                        onClick={() => window.location.href = '/inventory'}
                        className="flex items-center gap-2"
                    >
                        <Package className="h-4 w-4" />
                        View Inventory
                    </Button>
                </div>
            </motion.div>
        </div>
    );
}

export function ReorderClientPage({ initialSuggestions }: { initialSuggestions: ReorderSuggestion[] }) {
  const router = useRouter();
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();
  const [selectedSuggestions, setSelectedSuggestions] = useState<ReorderSuggestion[]>([]);

  const handleSelect = (suggestion: ReorderSuggestion, checked: boolean) => {
    setSelectedSuggestions(prev => 
      checked ? [...prev, suggestion] : prev.filter(s => s.sku !== suggestion.sku)
    );
  };

  const handleSelectAll = (checked: boolean) => {
    setSelectedSuggestions(checked ? initialSuggestions : []);
  };
  
  const handleCreatePOs = () => {
    startTransition(async () => {
        if (selectedSuggestions.length === 0) {
            toast({ variant: 'destructive', title: 'No items selected', description: 'Please select items to create a purchase order for.' });
            return;
        }

        const result = await createPurchaseOrdersFromSuggestions(selectedSuggestions);
        
        if (result.success) {
            toast({
                title: 'Purchase Orders Created!',
                description: `${result.createdPoCount || 0} purchase order(s) have been generated.`,
            });
            // Refresh data on both pages
            router.push('/purchase-orders');
            router.refresh();
        } else {
            toast({
                variant: 'destructive',
                title: 'Error Creating Purchase Orders',
                description: result.error || 'An unexpected error occurred.',
            });
        }
    });
  };
  
  const handleExport = () => {
    startTransition(async () => {
        if (selectedSuggestions.length === 0) {
            toast({ variant: 'destructive', title: 'No items selected', description: 'Please select items to export.' });
            return;
        }

        const result = await exportReorderSuggestions(selectedSuggestions);
        if (result.success && result.data) {
            const blob = new Blob([result.data], { type: 'text/csv;charset=utf-8;' });
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.setAttribute('download', `reorder-report-${new Date().toISOString().split('T')[0]}.csv`);
            link.style.visibility = 'hidden';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            toast({ title: 'Export Complete', description: 'Your reorder report has been downloaded.' });
        } else {
            toast({ variant: 'destructive', title: 'Export Failed', description: result.error });
        }
    });
  };
  
  // Show empty state when no suggestions
  if (!initialSuggestions || initialSuggestions.length === 0) {
    return <EmptyReorderState />;
  }
  
  const isAllSelected = initialSuggestions.length > 0 && selectedSuggestions.length === initialSuggestions.length;
  
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>AI-Enhanced Reorder Suggestions</CardTitle>
          <CardDescription>Select items to automatically generate purchase orders. The AI has adjusted quantities based on historical sales data and seasonality.</CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <div className="max-h-[65vh] overflow-auto">
            <Table>
              <TableHeader className="sticky top-0 z-10 bg-background/80 backdrop-blur-sm">
                <TableRow>
                  <TableHead className="w-12">
                    <Checkbox
                        checked={isAllSelected}
                        onCheckedChange={handleSelectAll}
                        aria-label="Select all rows"
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
                        onCheckedChange={(checked) => { handleSelect(suggestion, !!checked); }}
                        aria-label={`Select row for ${suggestion.product_name}`}
                      />
                    </TableCell>
                    <TableCell>
                        <div className="font-medium">{suggestion.product_name}</div>
                        <div className="text-xs text-muted-foreground">{suggestion.sku}</div>
                    </TableCell>
                    <TableCell>
                        {suggestion.supplier_name ? (
                            <span>{suggestion.supplier_name}</span>
                        ) : (
                            <TooltipProvider>
                                <Tooltip>
                                    <TooltipTrigger asChild>
                                        <span className="flex items-center gap-1 text-muted-foreground cursor-help">
                                            <Info className="h-4 w-4" />
                                            No Supplier
                                        </span>
                                    </TooltipTrigger>
                                    <TooltipContent>
                                        <p>Assign a supplier on the PO creation screen.</p>
                                    </TooltipContent>
                                </Tooltip>
                            </TooltipProvider>
                        )}
                    </TableCell>
                    <TableCell className="text-right font-tabular">{suggestion.current_quantity}</TableCell>
                    <TableCell className="text-right text-muted-foreground font-tabular">{suggestion.base_quantity}</TableCell>
                    <TableCell className="text-right font-bold text-primary font-tabular">{suggestion.suggested_reorder_quantity}</TableCell>
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
                        <Button onClick={handleExport} variant="outline" size="sm" disabled={isPending}>
                             <Download className="mr-2 h-4 w-4" /> Export to CSV
                        </Button>
                        <Button onClick={handleCreatePOs} size="sm" disabled={isPending}>
                            {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                             <ShoppingCart className="mr-2 h-4 w-4" /> Create PO(s)
                        </Button>
                    </div>
                </motion.div>
            )}
        </AnimatePresence>
    </div>
  );
}
