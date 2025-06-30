
'use client';

import { useState, useTransition } from 'react';
import { useFormStatus } from 'react-dom';
import { handleDataImport, type ImportResult } from '@/app/(app)/import/actions';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { AlertTriangle, CheckCircle, FileUp, Loader2, Table } from 'lucide-react';
import { CSRFInput } from '../auth/csrf-input';
import { useToast } from '@/hooks/use-toast';

const importOptions = {
    inventory: {
        label: 'Inventory',
        description: 'Import your core inventory data, including SKU, name, quantity, and cost.',
        columns: ['sku', 'name', 'quantity', 'cost', 'reorder_point', 'category', 'last_sold_date'],
    },
    suppliers: {
        label: 'Suppliers / Vendors',
        description: 'Import your supplier information.',
        columns: ['vendor_name', 'contact_info', 'address', 'terms', 'account_number'],
    },
    supplier_catalogs: {
        label: 'Supplier Catalogs',
        description: "Import supplier-specific product info like cost, MOQ, and lead times.",
        columns: ['supplier_id', 'sku', 'supplier_sku', 'product_name', 'unit_cost', 'moq', 'lead_time_days'],
    },
    reorder_rules: {
        label: 'Reorder Rules',
        description: "Import your custom reorder rules for products.",
        columns: ['sku', 'rule_type', 'min_stock', 'max_stock', 'reorder_quantity'],
    },
    locations: {
        label: 'Locations',
        description: "Import your warehouses or other stock locations.",
        columns: ['name', 'address', 'is_default'],
    },
};

type DataType = keyof typeof importOptions;

function SubmitButton() {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" disabled={pending} className="w-full">
            {pending ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Processing...</> : <><FileUp className="mr-2 h-4 w-4" /> Import Data</>}
        </Button>
    );
}

function ImportResultsCard({ results }: { results: Omit<ImportResult, 'success'> }) {
    const hasErrors = (results.errorCount || 0) > 0;
    const alertVariant = hasErrors ? 'destructive' : 'default';
    const Icon = hasErrors ? AlertTriangle : CheckCircle;
    
    return (
        <Card>
            <CardHeader>
                <CardTitle>Import Results</CardTitle>
            </CardHeader>
            <CardContent>
                <Alert variant={alertVariant} className="mb-4">
                    <Icon className="h-4 w-4" />
                    <AlertTitle>{results.summaryMessage}</AlertTitle>
                </Alert>

                {hasErrors && results.errors && (
                    <div>
                        <h3 className="mb-2 font-semibold">Error Details:</h3>
                        <div className="max-h-60 overflow-y-auto rounded-md border bg-muted p-2">
                           <ul className="space-y-1 text-sm">
                                {results.errors.map((err, index) => (
                                    <li key={index} className="flex gap-2">
                                        <span className="font-mono text-muted-foreground">[Row {err.row}]</span>
                                        <span className="text-destructive">{err.message}</span>
                                    </li>
                                ))}
                           </ul>
                        </div>
                    </div>
                )}
            </CardContent>
        </Card>
    );
}


export function ImporterClientPage() {
    const [dataType, setDataType] = useState<DataType>('inventory');
    const [results, setResults] = useState<Omit<ImportResult, 'success'> | null>(null);
    const [isPending, startTransition] = useTransition();
    const { toast } = useToast();

    const handleSubmit = (formData: FormData) => {
        setResults(null);
        startTransition(async () => {
            const result = await handleDataImport(formData);
            if (result.success) {
                setResults(result);
            } else {
                 toast({
                    variant: 'destructive',
                    title: 'Import Failed',
                    description: result.summaryMessage
                });
                setResults(null);
            }
        });
    };

    return (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
            <Card className="lg:col-span-1">
                <CardHeader>
                    <CardTitle>Upload Your Data</CardTitle>
                    <CardDescription>
                        Select the type of data you want to import and upload the corresponding CSV file.
                    </CardDescription>
                </CardHeader>
                <form action={handleSubmit}>
                    <CardContent className="space-y-6">
                        <CSRFInput />
                        <div className="space-y-2">
                            <Label htmlFor="data-type">Data Type</Label>
                            <Select name="dataType" value={dataType} onValueChange={(value) => setDataType(value as DataType)} required>
                                <SelectTrigger id="data-type">
                                    <SelectValue placeholder="Select a data type to import" />
                                </SelectTrigger>
                                <SelectContent>
                                    {Object.entries(importOptions).map(([key, { label }]) => (
                                        <SelectItem key={key} value={key}>{label}</SelectItem>
                                    ))}
                                </SelectContent>
                            </Select>
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="file">CSV File</Label>
                            <Input id="file" name="file" type="file" accept=".csv" required />
                        </div>
                        <Alert>
                            <Table className="h-4 w-4" />
                            <AlertTitle>Required CSV Columns</AlertTitle>
                            <AlertDescription>
                                Ensure your CSV file has the following columns:
                                <div className="mt-2 flex flex-wrap gap-2">
                                    {importOptions[dataType].columns.map(col => (
                                        <code key={col} className="text-xs font-mono bg-muted text-muted-foreground px-2 py-1 rounded-md">{col}</code>
                                    ))}
                                </div>
                            </AlertDescription>
                        </Alert>
                    </CardContent>
                    <CardFooter>
                       <SubmitButton />
                    </CardFooter>
                </form>
            </Card>

            <div className="lg:col-span-1">
                {isPending && !results && (
                     <Card className="h-full flex flex-col items-center justify-center text-center p-8 border-dashed">
                        <Loader2 className="h-12 w-12 text-muted-foreground animate-spin" />
                        <CardTitle className="mt-4">Processing File...</CardTitle>
                        <CardDescription className="mt-2 max-w-xs">
                            Validating rows and importing data. This may take a moment for large files. Please wait.
                        </CardDescription>
                    </Card>
                )}
                {results && (
                    <ImportResultsCard results={results} />
                )}
                {!isPending && !results && (
                     <Card className="h-full flex flex-col items-center justify-center text-center p-8 border-dashed">
                        <FileUp className="h-12 w-12 text-muted-foreground" />
                        <CardTitle className="mt-4">Ready to Import</CardTitle>
                        <CardDescription className="mt-2">
                            Your import results will appear here once the file is processed.
                        </CardDescription>
                    </Card>
                )}
            </div>
        </div>
    );
}
