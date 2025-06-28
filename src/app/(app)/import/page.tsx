
'use client';

import React, { useState, useEffect } from 'react';
import * as XLSX from 'xlsx';
import Papa from 'papaparse';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { useToast } from '@/hooks/use-toast';
import { AlertCircle, CheckCircle, UploadCloud } from 'lucide-react';
import { SidebarTrigger } from '@/components/ui/sidebar';
import Confetti from 'react-confetti';

type Step = 1 | 2 | 3;
type ParsedRow = Record<string, string | number>;

const INVOCHAT_FIELDS = {
  sku: 'SKU',
  name: 'Product Name',
  quantity: 'Quantity',
  cost: 'Unit Cost',
};
type InvochatFieldKey = keyof typeof INVOCHAT_FIELDS;

// Simple hook to get window size
function useWindowSize() {
  const [size, setSize] = useState([0, 0]);
  useEffect(() => {
    function updateSize() {
      setSize([window.innerWidth, window.innerHeight]);
    }
    window.addEventListener('resize', updateSize);
    updateSize();
    return () => window.removeEventListener('resize', updateSize);
  }, []);
  return { width: size[0], height: size[1] };
}

export default function ImportPage() {
  const [currentStep, setCurrentStep] = useState<Step>(1);
  const [file, setFile] = useState<File | null>(null);
  const [parsedData, setParsedData] = useState<ParsedRow[]>([]);
  const [headers, setHeaders] = useState<string[]>([]);
  const [mappings, setMappings] = useState<Record<InvochatFieldKey, string>>({
    sku: '',
    name: '',
    quantity: '',
    cost: '',
  });
  const [isParsing, setIsParsing] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [showConfetti, setShowConfetti] = useState(false);
  const { width, height } = useWindowSize();
  const { toast } = useToast();

  const handleFileDrop = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.currentTarget.classList.remove('border-primary');
    const droppedFile = e.dataTransfer.files[0];
    if (droppedFile) {
      processFile(droppedFile);
    }
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0];
    if (selectedFile) {
      processFile(selectedFile);
    }
  };
  
  const autoMapHeaders = (fileHeaders: string[]) => {
    const newMappings: Record<InvochatFieldKey, string> = { sku: '', name: '', quantity: '', cost: '' };
    const lowerCaseHeaders = fileHeaders.map(h => h.toLowerCase().trim());

    Object.keys(INVOCHAT_FIELDS).forEach(key => {
        const fieldKey = key as InvochatFieldKey;
        const potentialMatches = [
            INVOCHAT_FIELDS[fieldKey].toLowerCase(),
            fieldKey,
        ];
        if (fieldKey === 'sku') potentialMatches.push('part #', 'item id');
        if (fieldKey === 'name') potentialMatches.push('description', 'product');
        if (fieldKey === 'quantity') potentialMatches.push('qty', 'on hand', 'stock');
        if (fieldKey === 'cost') potentialMatches.push('unit cost', 'price');
        
        for (const match of potentialMatches) {
            const headerIndex = lowerCaseHeaders.findIndex(h => h.includes(match));
            if (headerIndex !== -1) {
                newMappings[fieldKey] = fileHeaders[headerIndex];
                break;
            }
        }
    });

    setMappings(newMappings);
  };

  const resetState = () => {
      setCurrentStep(1);
      setFile(null);
      setParsedData([]);
      setHeaders([]);
      setMappings({ sku: '', name: '', quantity: '', cost: '' });
  };

  const processFile = (selectedFile: File) => {
    if (!['text/csv', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.ms-excel'].includes(selectedFile.type)) {
      toast({ variant: 'destructive', title: 'Invalid File Type', description: 'Please upload a CSV or XLSX file.' });
      return;
    }
    setFile(selectedFile);
    setIsParsing(true);

    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const fileContent = e.target?.result;
        if (!fileContent) throw new Error("Could not read file content.");

        let jsonData: ParsedRow[];
        let fileHeaders: string[];

        if (selectedFile.type === 'text/csv') {
          const result = Papa.parse(fileContent as string, {
            header: true,
            skipEmptyLines: true,
          });
          if(result.errors.length > 0) {
              throw new Error("Error parsing CSV file.");
          }
          jsonData = result.data as ParsedRow[];
          fileHeaders = result.meta.fields || [];
        } else {
          const workbook = XLSX.read(fileContent, { type: 'binary' });
          const sheetName = workbook.SheetNames[0];
          const worksheet = workbook.Sheets[sheetName];
          jsonData = XLSX.utils.sheet_to_json(worksheet) as ParsedRow[];
          fileHeaders = jsonData.length > 0 ? Object.keys(jsonData[0]) : [];
        }
        
        setParsedData(jsonData);
        setHeaders(fileHeaders);
        autoMapHeaders(fileHeaders);
        setCurrentStep(2);
      } catch (error) {
        toast({ variant: 'destructive', title: 'Parsing Error', description: 'Could not process the file. Please check its format.' });
      } finally {
        setIsParsing(false);
      }
    };
    reader.onerror = () => {
        toast({ variant: 'destructive', title: 'File Read Error', description: 'There was an error reading the file.' });
        setIsParsing(false);
    }

    reader.readAsBinaryString(selectedFile);
  };

  const handleMappingChange = (invochatField: InvochatFieldKey, fileHeader: string) => {
    setMappings(prev => ({ ...prev, [invochatField]: fileHeader }));
  };

  const handleImport = async () => {
    setIsImporting(true);
    
    try {
      // Prepare data for API
      const itemsToImport = validatedData.valid.map(row => ({
        sku: row[mappings.sku],
        name: row[mappings.name],
        quantity: row[mappings.quantity],
        cost: row[mappings.cost],
      }));
      
      const response = await fetch('/api/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ items: itemsToImport }),
      });
      
      const result = await response.json();
      
      if (!response.ok) {
        throw new Error(result.error || 'Import failed');
      }
      
      toast({ 
        title: "Import Successful", 
        description: `${result.count} products have been imported.`
      });
      
      setShowConfetti(true);
      setTimeout(() => setShowConfetti(false), 6000); // Hide confetti after 6 seconds

      // Reset state for another import
      resetState();
      
    } catch (error: any) {
      toast({ 
        variant: 'destructive',
        title: "Import Failed", 
        description: error.message 
      });
      // Also reset on failure so the user can try again
      resetState();
    } finally {
      setIsImporting(false);
    }
  };
  
  const validatedData = React.useMemo(() => {
    const valid: ParsedRow[] = [];
    const invalid: (ParsedRow & { error: string })[] = [];

    if (currentStep !== 3) return { valid, invalid };

    parsedData.forEach(row => {
      const sku = row[mappings.sku];
      const name = row[mappings.name];
      const quantity = row[mappings.quantity];

      if (!sku || !name) {
        invalid.push({ ...row, error: 'Missing SKU or Product Name' });
      } else if (quantity === undefined || quantity === null || isNaN(Number(quantity))) {
        invalid.push({ ...row, error: 'Quantity must be a number' });
      } else {
        valid.push(row);
      }
    });

    return { valid, invalid };
  }, [parsedData, mappings, currentStep]);

  const renderStepContent = () => {
    switch (currentStep) {
      case 1:
        return (
          <CardContent className="p-0">
            <label
              htmlFor="file-upload"
              className="relative flex flex-col items-center justify-center w-full py-12 border-2 border-dashed rounded-lg cursor-pointer transition-colors hover:bg-muted"
              onDragOver={(e) => {
                e.preventDefault();
                e.currentTarget.classList.add('border-primary');
              }}
              onDragLeave={(e) => e.currentTarget.classList.remove('border-primary')}
              onDrop={handleFileDrop}
            >
              <UploadCloud className="w-12 h-12 text-muted-foreground" />
              <h3 className="mt-4 text-lg font-semibold">Drag & drop your file here</h3>
              <p className="text-muted-foreground">or click to browse</p>
              <p className="text-xs text-muted-foreground mt-2">Supports: .xlsx, .csv (Max 10MB)</p>
              <input id="file-upload" type="file" className="hidden" onChange={handleFileSelect} accept=".csv, .xlsx, .xls" />
            </label>
             {isParsing && <Progress value={undefined} className="mt-4" />}
          </CardContent>
        );
      case 2:
        return (
          <CardContent>
            <h3 className="text-lg font-semibold mb-2">Map Your Columns</h3>
            <p className="text-muted-foreground mb-4">
              Match the columns from your file ({file?.name}) to InvoChat's fields.
            </p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
              {Object.entries(INVOCHAT_FIELDS).map(([key, label]) => (
                <div key={key} className="space-y-1">
                  <label className="font-medium text-sm">{label} <span className="text-destructive">*</span></label>
                  <Select value={mappings[key as InvochatFieldKey]} onValueChange={(val) => handleMappingChange(key as InvochatFieldKey, val)}>
                    <SelectTrigger>
                      <SelectValue placeholder="Select a column..." />
                    </SelectTrigger>
                    <SelectContent>
                      {headers.map(h => <SelectItem key={h} value={h}>{h}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              ))}
            </div>

            <h4 className="font-semibold mb-2">Data Preview</h4>
            <div className="rounded-md border max-h-60 overflow-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    {headers.slice(0, 5).map(h => <TableHead key={h}>{h}</TableHead>)}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {parsedData.slice(0, 5).map((row, i) => (
                    <TableRow key={i}>
                      {headers.slice(0, 5).map(h => <TableCell key={h}>{row[h]}</TableCell>)}
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
            <div className="flex justify-end mt-6">
                <Button onClick={() => setCurrentStep(1)} variant="outline" className="mr-2">Back</Button>
                <Button onClick={() => setCurrentStep(3)}>Review Data</Button>
            </div>
          </CardContent>
        );
      case 3:
        return (
            <CardContent>
                <h3 className="text-lg font-semibold mb-2">Review & Import</h3>
                <div className="flex items-center gap-4 mb-4 p-4 bg-muted rounded-lg">
                    <div className="flex items-center gap-2 text-green-600">
                        <CheckCircle className="h-5 w-5" />
                        <span>{validatedData.valid.length} valid rows</span>
                    </div>
                    <div className="flex items-center gap-2 text-destructive">
                        <AlertCircle className="h-5 w-5" />
                        <span>{validatedData.invalid.length} invalid rows</span>
                    </div>
                </div>

                {validatedData.invalid.length > 0 && (
                    <>
                        <h4 className="font-semibold mb-2">Rows with Errors</h4>
                         <div className="rounded-md border max-h-60 overflow-auto">
                            <Table>
                                <TableHeader>
                                    <TableRow>
                                        <TableHead>SKU</TableHead>
                                        <TableHead>Product Name</TableHead>
                                        <TableHead>Reason</TableHead>
                                    </TableRow>
                                </TableHeader>
                                <TableBody>
                                    {validatedData.invalid.slice(0,10).map((row, i) => (
                                        <TableRow key={i}>
                                            <TableCell>{String(row[mappings.sku] || 'N/A')}</TableCell>
                                            <TableCell>{String(row[mappings.name] || 'N/A')}</TableCell>
                                            <TableCell className="text-destructive">{row.error}</TableCell>
                                        </TableRow>
                                    ))}
                                </TableBody>
                            </Table>
                         </div>
                    </>
                )}
                
                <div className="mt-6 flex justify-end items-center">
                    <Button onClick={() => setCurrentStep(2)} variant="outline" className="mr-2">Back to Mapping</Button>
                    <Button onClick={handleImport} disabled={validatedData.valid.length === 0 || isImporting}>
                        {isImporting ? "Importing..." : `Import ${validatedData.valid.length} Products`}
                    </Button>
                </div>
                 {isImporting && <Progress value={undefined} className="mt-4" />}
            </CardContent>
        );
      default:
        return null;
    }
  };

  const stepDescriptions = [
      { step: 1, title: 'Upload File', description: 'Select your inventory file' },
      { step: 2, title: 'Map Columns', description: 'Match your data to our fields' },
      { step: 3, title: 'Review & Import', description: 'Finalize and start the import' }
  ]

  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
      {showConfetti && <Confetti width={width} height={height} recycle={false} numberOfPieces={500} />}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Import Inventory</h1>
        </div>
      </div>
      
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
              <div className="flex-1">
                <CardTitle>{stepDescriptions[currentStep-1].title}</CardTitle>
                <CardDescription>{stepDescriptions[currentStep-1].description}</CardDescription>
              </div>
              <div className="text-sm text-muted-foreground">Step {currentStep} of 3</div>
          </div>
          <Progress value={(currentStep / 3) * 100} className="w-full mt-2" />
        </CardHeader>
        {renderStepContent()}
      </Card>
    </div>
  );
}
