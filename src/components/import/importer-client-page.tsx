
'use client';

import { useState, useTransition, DragEvent, useRef, useEffect } from 'react';
import { handleDataImport, type ImportResult } from '@/app/import/actions';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { AlertTriangle, CheckCircle, Loader2, Table, UploadCloud } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { cn } from '@/lib/utils';

const CSRF_FORM_NAME = 'csrf_token';
const CSRF_COOKIE_NAME = 'csrf_token';

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
    const [isDragging, setIsDragging] = useState(false);
    const [fileName, setFileName] = useState<string | null>(null);
    const formRef = useRef<HTMLFormElement>(null);
    const [csrfToken, setCsrfToken] = useState<string | null>(null);

    useEffect(() => {
        const token = document.cookie
          .split('; ')
          .find(row => row.startsWith(`${CSRF_COOKIE_NAME}=`))
          ?.split('=')[1];
        setCsrfToken(token || null);
    }, []);

    const handleFormSubmit = (event: React.FormEvent<HTMLFormElement>) => {
        event.preventDefault();
        const formData = new FormData(event.currentTarget);
        const file = formData.get('file') as File;

        if (!file || file.size === 0) {
            toast({ variant: 'destructive', title: 'No file selected', description: 'Please choose a file to upload.' });
            return;
        }

        if (!csrfToken) {
            toast({ variant: 'destructive', title: 'Error', description: 'Could not verify form. Please refresh the page.' });
            return;
        }

        setFileName(file.name);
        setResults(null);

        startTransition(async () => {
            const result = await handleDataImport(formData);
            if (result.success) {
                setResults(result);
                formRef.current?.reset();
                setFileName(null);
            } else {
                 toast({ variant: 'destructive', title: 'Import Failed', description: result.summaryMessage });
                setResults(null);
            }
        });
    };

    const processDroppedFile = (file: File | null) => {
        if (!file || !formRef.current) return;
        
        const dataTransfer = new DataTransfer();
        dataTransfer.items.add(file);

        const fileInput = formRef.current.querySelector<HTMLInputElement>('input[name="file"]');
        if (fileInput) {
            fileInput.files = dataTransfer.files;
        }
        
        // Trigger form submission
        formRef.current.requestSubmit();
    };

    const handleDragEnter = (e: DragEvent<HTMLFormElement>) => { e.preventDefault(); e.stopPropagation(); setIsDragging(true); };
    const handleDragLeave = (e: DragEvent<HTMLFormElement>) => { e.preventDefault(); e.stopPropagation(); setIsDragging(false); };
    const handleDragOver = (e: DragEvent<HTMLFormElement>) => { e.preventDefault(); e.stopPropagation(); };
    const handleDrop = (e: DragEvent<HTMLFormElement>) => {
        e.preventDefault();
        e.stopPropagation();
        setIsDragging(false);
        const files = e.dataTransfer.files;
        if (files && files.length > 0) {
            processDroppedFile(files[0]);
        }
    };

    return (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
            <form ref={formRef} onSubmit={handleFormSubmit}
                onDragEnter={handleDragEnter}
                onDragLeave={handleDragLeave}
                onDragOver={handleDragOver}
                onDrop={handleDrop}
            >
                <Card className="lg:col-span-1">
                        <CardHeader>
                            <CardTitle>Upload Your Data</CardTitle>
                            <CardDescription>
                                Select the data type, then drag and drop your CSV file or click to browse.
                            </CardDescription>
                        </CardHeader>
                        <CardContent className="space-y-6">
                            <input type="hidden" name="dataType" value={dataType} />
                            {csrfToken && <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken} />}
                            <div className="space-y-2">
                                <Label htmlFor="data-type">1. Select Data Type</Label>
                                <Select value={dataType} onValueChange={(value) => setDataType(value as DataType)} required>
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
                                <Label>2. Upload File</Label>
                                <div 
                                    className={cn(
                                        "relative flex flex-col items-center justify-center w-full h-48 border-2 border-dashed rounded-lg cursor-pointer bg-muted/50 hover:bg-muted transition-colors",
                                        isDragging && "border-primary bg-primary/10"
                                    )}
                                >
                                    <div className="flex flex-col items-center justify-center pt-5 pb-6 text-center">
                                        <UploadCloud className={cn("w-10 h-10 mb-3 text-muted-foreground", isDragging && "text-primary")} />
                                        {fileName ? (
                                            <>
                                                <p className="font-semibold text-primary">{fileName}</p>
                                                <p className="text-xs text-muted-foreground">Drop another file to replace</p>
                                            </>
                                        ) : (
                                            <>
                                                <p className="mb-2 text-sm text-foreground">
                                                    <span className="font-semibold">Click to upload</span> or drag and drop
                                                </p>
                                                <p className="text-xs text-muted-foreground">CSV files supported (up to 10MB)</p>
                                            </>
                                        )}
                                    </div>
                                    <Input 
                                        id="file" 
                                        name="file" 
                                        type="file" 
                                        accept=".csv" 
                                        className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                                        onChange={(e) => {
                                            if (e.target.files && e.target.files.length > 0) {
                                                formRef.current?.requestSubmit();
                                            }
                                        }}
                                    />
                                </div>
                            </div>

                            <Alert>
                                <Table className="h-4 w-4" />
                                <AlertTitle>Required CSV Columns for '{importOptions[dataType].label}'</AlertTitle>
                                <AlertDescription>
                                    <div className="mt-2 flex flex-wrap gap-2">
                                        {importOptions[dataType].columns.map(col => (
                                            <code key={col} className="text-xs font-mono bg-muted text-muted-foreground px-2 py-1 rounded-md">{col}</code>
                                        ))}
                                    </div>
                                </AlertDescription>
                            </Alert>
                        </CardContent>
                </Card>
            </form>
            <div className="lg:col-span-1">
                {isPending ? (
                     <Card className="h-full flex flex-col items-center justify-center text-center p-8 border-dashed">
                        <Loader2 className="h-12 w-12 text-muted-foreground animate-spin" />
                        <CardTitle className="mt-4">Processing File...</CardTitle>
                        <CardDescription className="mt-2 max-w-xs">
                            Validating rows and importing data. This may take a moment.
                        </CardDescription>
                    </Card>
                ) : results ? (
                    <ImportResultsCard results={results} />
                ) : (
                     <Card className="h-full flex flex-col items-center justify-center text-center p-8 border-dashed">
                        <UploadCloud className="h-12 w-12 text-muted-foreground" />
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
