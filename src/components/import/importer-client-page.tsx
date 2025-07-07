
'use client';

import { useState, useTransition, DragEvent, useRef, useEffect, ChangeEvent } from 'react';
import { handleDataImport, getMappingSuggestions, type ImportResult } from '@/app/import/actions';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { AlertTriangle, CheckCircle, Info, Loader2, Table as TableIcon, UploadCloud, XCircle, Wand2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { cn } from '@/lib/utils';
import { ScrollArea } from '../ui/scroll-area';
import { Checkbox } from '../ui/checkbox';
import type { CsvMappingOutput } from '@/ai/flows/csv-mapping-flow';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '../ui/table';

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

function MappingSuggestions({ suggestions, onConfirm }: { suggestions: CsvMappingOutput, onConfirm: (mappings: Record<string, string>) => void }) {
    const confirmedMappings = suggestions.mappings.reduce((acc, m) => {
        acc[m.csvColumn] = m.dbField;
        return acc;
    }, {} as Record<string, string>);

    return (
        <Card className="mt-6 border-primary/30">
            <CardHeader>
                <CardTitle className="flex items-center gap-2"><Wand2 className="h-5 w-5 text-primary" /> AI Mapping Suggestions</CardTitle>
                <CardDescription>The AI has suggested the following column mappings. Unmapped columns will be ignored during the import.</CardDescription>
            </CardHeader>
            <CardContent>
                <ScrollArea className="h-48">
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Your CSV Column</TableHead>
                                <TableHead>Maps to DB Field</TableHead>
                                <TableHead className="text-right">Confidence</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {suggestions.mappings.map(m => (
                                <TableRow key={m.csvColumn}>
                                    <TableCell className="font-medium">{m.csvColumn}</TableCell>
                                    <TableCell className="font-semibold text-primary">{m.dbField}</TableCell>
                                    <TableCell className="text-right">{(m.confidence * 100).toFixed(0)}%</TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                </ScrollArea>
                {suggestions.unmappedColumns.length > 0 && (
                    <div className="mt-4 text-sm">
                        <p className="font-semibold">Unmapped columns (will be ignored):</p>
                        <p className="text-muted-foreground text-xs">{suggestions.unmappedColumns.join(', ')}</p>
                    </div>
                )}
            </CardContent>
            <CardFooter>
                <Button onClick={() => onConfirm(confirmedMappings)}>Confirm Mappings &amp; Start Import</Button>
            </CardFooter>
        </Card>
    );
}

function ImportResultsCard({ results, onClear }: { results: Omit<ImportResult, 'success'>; onClear: () => void }) {
    const hasErrors = (results.errorCount || 0) > 0;
    const alertVariant = results.isDryRun ? 'default' : (hasErrors ? 'destructive' : 'default');
    const Icon = results.isDryRun ? Info : (hasErrors ? XCircle : CheckCircle);
    const title = results.isDryRun ? (hasErrors ? 'Dry Run Failed' : 'Dry Run Successful') : (hasErrors ? 'Import Had Errors' : 'Import Successful');
    
    return (
        <Card>
            <CardHeader className="flex flex-row items-start justify-between">
                <div>
                    <CardTitle className="flex items-center gap-2">
                        <Icon className={cn("h-5 w-5", hasErrors && 'text-destructive', !hasErrors && 'text-success')} />
                        {title}
                    </CardTitle>
                    <CardDescription>{results.summaryMessage}</CardDescription>
                </div>
                <Button variant="ghost" size="sm" onClick={onClear}>Clear</Button>
            </CardHeader>
            <CardContent>
                {hasErrors && results.errors && (
                    <div>
                        <h3 className="mb-2 font-semibold">Error Details:</h3>
                        <ScrollArea className="h-60 rounded-md border bg-muted p-2">
                           <ul className="space-y-1 text-sm">
                                {results.errors.map((err, index) => (
                                    <li key={index} className="flex gap-2 p-1 border-b">
                                        <span className="font-mono text-muted-foreground">[Row {err.row}]</span>
                                        <span className="text-destructive">{err.message}</span>
                                    </li>
                                ))}
                           </ul>
                        </ScrollArea>
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
    const [file, setFile] = useState<File | null>(null);
    const [dryRun, setDryRun] = useState(true);
    const [csrfToken, setCsrfToken] = useState<string | null>(null);
    const [mappingSuggestions, setMappingSuggestions] = useState<CsvMappingOutput | null>(null);

    useEffect(() => {
        const token = document.cookie
          .split('; ')
          .find(row => row.startsWith(`${CSRF_COOKIE_NAME}=`))
          ?.split('=')[1];
        setCsrfToken(token || null);
    }, []);

    const handleFormSubmit = (mappings: Record<string, string> = {}) => {
        if (!file) {
            toast({ variant: 'destructive', title: 'No file selected', description: 'Please choose a file to upload.' });
            return;
        }

        if (!csrfToken) {
            toast({ variant: 'destructive', title: 'Error', description: 'Could not verify form. Please refresh the page.' });
            return;
        }

        const formData = new FormData();
        formData.append('file', file);
        formData.append('dataType', dataType);
        formData.append('dryRun', String(dryRun));
        formData.append(CSRF_COOKIE_NAME, csrfToken);
        formData.append('mappings', JSON.stringify(mappings));

        setResults(null);
        setMappingSuggestions(null);

        startTransition(async () => {
            const result = await handleDataImport(formData);
            if (result.success) {
                setResults(result);
                if (!result.isDryRun && (result.errorCount === 0 || result.errorCount === undefined)) {
                    setFile(null);
                }
            } else {
                 toast({ variant: 'destructive', title: 'Import Failed', description: result.summaryMessage });
                setResults(null);
            }
        });
    };
    
    const handleGetMappingSuggestions = () => {
        if (!file || !csrfToken) return;
        
        const formData = new FormData();
        formData.append('file', file);
        formData.append(CSRF_COOKIE_NAME, csrfToken);

        setResults(null);
        setMappingSuggestions(null);

        startTransition(async () => {
            try {
                const suggestions = await getMappingSuggestions(formData);
                setMappingSuggestions(suggestions);
            } catch (e: any) {
                toast({ variant: 'destructive', title: 'AI Mapping Failed', description: e.message });
            }
        });
    };
    
    const handleFileChange = (e: ChangeEvent<HTMLInputElement>) => {
        const selectedFile = e.target.files?.[0];
        if (selectedFile) {
            setFile(selectedFile);
            setResults(null);
            setMappingSuggestions(null);
        }
    }
    
    const processDroppedFile = (droppedFile: File | null) => {
        if (!droppedFile) return;
        setFile(droppedFile);
        setResults(null);
        setMappingSuggestions(null);
    };

    const handleDragEnter = (e: DragEvent<HTMLDivElement>) => { e.preventDefault(); e.stopPropagation(); setIsDragging(true); };
    const handleDragLeave = (e: DragEvent<HTMLDivElement>) => { e.preventDefault(); e.stopPropagation(); setIsDragging(false); };
    const handleDragOver = (e: DragEvent<HTMLDivElement>) => { e.preventDefault(); e.stopPropagation(); };
    const handleDrop = (e: DragEvent<HTMLDivElement>) => {
        e.preventDefault();
        e.stopPropagation();
        setIsDragging(false);
        const files = e.dataTransfer.files;
        if (files && files.length > 0) {
            processDroppedFile(files[0]);
        }
    };

    return (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 items-start">
            <Card className="lg:col-span-1">
                <CardHeader>
                    <CardTitle>Upload Your Data</CardTitle>
                    <CardDescription>
                        Select the data type, then drag and drop your CSV file or click to browse.
                    </CardDescription>
                </CardHeader>
                <CardContent className="space-y-6">
                    <div className="space-y-2">
                        <Label>1. Select Data Type</Label>
                        <Select value={dataType} onValueChange={(value) => setDataType(value as DataType)} required>
                            <SelectTrigger>
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
                            onDragEnter={handleDragEnter}
                            onDragLeave={handleDragLeave}
                            onDragOver={handleDragOver}
                            onDrop={handleDrop}
                            className={cn(
                                "relative flex flex-col items-center justify-center w-full h-48 border-2 border-dashed rounded-lg cursor-pointer bg-muted/50 hover:bg-muted transition-colors",
                                isDragging && "border-primary bg-primary/10"
                            )}
                        >
                            <div className="flex flex-col items-center justify-center pt-5 pb-6 text-center">
                                <UploadCloud className={cn("w-10 h-10 mb-3 text-muted-foreground", isDragging && "text-primary")} />
                                {file?.name ? (
                                    <>
                                        <p className="font-semibold text-primary">{file.name}</p>
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
                                type="file" 
                                accept=".csv,text/csv,application/vnd.ms-excel" 
                                className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                                onChange={handleFileChange}
                            />
                        </div>
                    </div>
                     {file && (
                        <div className="space-y-4 rounded-lg border p-4">
                             <div className="flex items-center space-x-2">
                                <Checkbox id="dryRun" checked={dryRun} onCheckedChange={(checked) => setDryRun(!!checked)} />
                                <div className="grid gap-1.5 leading-none">
                                    <label
                                        htmlFor="dryRun"
                                        className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
                                    >
                                        Dry Run Mode
                                    </label>
                                    <p className="text-sm text-muted-foreground">
                                        Validate the file for errors without saving any data to the database.
                                    </p>
                                </div>
                            </div>
                            <div className="flex flex-col sm:flex-row gap-2">
                                <Button onClick={() => handleFormSubmit({})} disabled={isPending} className="flex-1">
                                    {isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <TableIcon className="mr-2 h-4 w-4" />}
                                    Start Import
                                </Button>
                                <Button onClick={handleGetMappingSuggestions} variant="outline" disabled={isPending} className="flex-1">
                                    {isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Wand2 className="mr-2 h-4 w-4" />}
                                    Suggest Mappings with AI
                                </Button>
                            </div>
                        </div>
                    )}
                </CardContent>
            </Card>

            <div className="lg:col-span-1">
                {isPending ? (
                     <Card className="h-full flex flex-col items-center justify-center text-center p-8 border-dashed">
                        <Loader2 className="h-12 w-12 text-muted-foreground animate-spin" />
                        <CardTitle className="mt-4">Processing...</CardTitle>
                        <CardDescription className="mt-2 max-w-xs">
                           The system is analyzing your file. This may take a moment.
                        </CardDescription>
                    </Card>
                ) : results ? (
                    <ImportResultsCard results={results} onClear={() => { setResults(null); setFile(null); setMappingSuggestions(null); }} />
                ) : mappingSuggestions ? (
                     <MappingSuggestions suggestions={mappingSuggestions} onConfirm={handleFormSubmit} />
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

    