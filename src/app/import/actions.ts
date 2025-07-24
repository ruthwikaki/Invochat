
'use server';

import { headers } from 'next/headers';
import Papa from 'papaparse';
import { z } from 'zod';
import { ProductCostImportSchema, SupplierImportSchema, HistoricalSalesImportSchema } from '@/app/import/schemas';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { invalidateCompanyCache, rateLimit } from '@/lib/redis';
import { validateCSRF } from '@/lib/csrf';
import { getErrorMessage, logError } from '@/lib/error-handler';
import type { CsvMappingOutput } from '@/types';
import { revalidatePath } from 'next/cache';
import { suggestCsvMappings } from '@/ai/flows/csv-mapping-flow';
import { getAuthContext } from '@/app/data-actions';
import { checkUserPermission, refreshMaterializedViews } from '@/services/database';
import type { Json } from '@/types/database.types';

const MAX_FILE_SIZE_MB = 10;
const MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024;
const BATCH_SIZE = 500;

export type ImportResult = {
  success: boolean;
  isDryRun: boolean;
  importId?: string;
  processedCount?: number;
  errorCount?: number;
  errors?: { row: number; message: string; data: Record<string, unknown> }[];
  summary?: Record<string, unknown>;
  summaryMessage: string;
};


async function createImportJob(companyId: string, userId: string, importType: string, fileName: string, totalRows: number) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('imports').insert({
        company_id: companyId,
        created_by: userId,
        import_type: importType,
        file_name: fileName,
        total_rows: totalRows,
        status: 'processing'
    }).select('id').single();

    if (error) throw new Error('Could not create import job entry in database.');
    return data.id;
}

async function updateImportJob(importId: string, updates: Partial<ImportResult>) {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('imports').update({
        processed_rows: updates.processedCount,
        failed_rows: updates.errorCount,
        errors: updates.errors as Json,
        summary: updates.summary as Json,
        status: (updates.errorCount ?? 0) > 0 ? 'completed_with_errors' : 'completed',
        completed_at: new Date().toISOString()
    }).eq('id', importId);

    if (error) {
      logError(error, { context: 'Failed to update import job', importId });
    }
}

async function failImportJob(importId: string, errorMessage: string) {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('imports').update({
        status: 'failed',
        errors: [{ row: 0, message: errorMessage, data: {} }] as Json,
        completed_at: new Date().toISOString()
    }).eq('id', importId);
     if (error) {
      logError(error, { context: 'Failed to mark import job as failed', importId });
    }
}


async function processCsv<T extends z.ZodType>(
    fileContentStream: NodeJS.ReadableStream,
    schema: T,
    companyId: string,
    userId: string,
    isDryRun: boolean,
    mappings: Record<string, string>,
    importType: string,
    importId?: string
): Promise<Omit<ImportResult, 'success' | 'isDryRun'>> {
    const supabase = getServiceRoleClient();
    if (!supabase && !isDryRun) {
        throw new Error('Supabase admin client not initialized.');
    }

    const rpcMap = {
        'product-costs': 'batch_upsert_costs',
        'suppliers': 'batch_upsert_suppliers',
        'historical-sales': 'batch_import_sales'
    };
    const rpcToCall = rpcMap[importType as keyof typeof rpcMap];
    if (!rpcToCall && !isDryRun) {
        throw new Error(`Unsupported import type for batch processing: ${importType}`);
    }

    let batch: z.infer<T>[] = [];
    const validationErrors: { row: number; message: string; data: Record<string, unknown> }[] = [];
    let rowCount = 0;
    let processedCount = 0;

    const processBatch = async (currentBatch: z.infer<T>[]) => {
        if (currentBatch.length === 0) return;
        if (isDryRun) {
            processedCount += currentBatch.length;
            return;
        }

        const { error: dbError } = await supabase.rpc(rpcToCall, { p_records: currentBatch, p_company_id: companyId, p_user_id: userId });
        if (dbError) {
            logError(dbError, { context: `Transactional database error for ${importType}` });
            validationErrors.push({ row: rowCount, message: `Database error during batch import: ${dbError.message}`, data: {} });
        } else {
            processedCount += currentBatch.length;
        }
    };
    
    return new Promise((resolve, reject) => {
        const parser = Papa.parse(Papa.NODE_STREAM_INPUT, {
            header: true,
            skipEmptyLines: true,
            transformHeader: header => header.trim().toLowerCase(),
            step: async (results, parser) => {
                parser.pause(); // Pause stream to process the row
                rowCount++;
                if (rowCount > 10000) {
                    parser.abort();
                    reject(new Error('File exceeds the maximum of 10,000 rows per import.')); 
                    return;
                }

                let row = results.data as Record<string, unknown>;
                if (Object.keys(mappings).length > 0) {
                    const newRow: Record<string, unknown> = {};
                    for (const originalHeader in row) {
                        if (Object.prototype.hasOwnProperty.call(row, originalHeader)) {
                            const mappedHeader = Object.prototype.hasOwnProperty.call(mappings, originalHeader) ? mappings[originalHeader] : null;
                            if (mappedHeader && mappedHeader !== '__proto__') {
                                newRow[mappedHeader] = row[originalHeader];
                            }
                        }
                    }
                    row = newRow;
                }

                row.company_id = companyId;
                const result = schema.safeParse(row);

                if (result.success) {
                    batch.push(result.data);
                    if (batch.length >= BATCH_SIZE) {
                        await processBatch(batch);
                        batch = []; // Clear the batch
                    }
                } else {
                    const errorMessage = result.error.issues.map(issue => `${issue.path.join('.')}: ${issue.message}`).join(', ');
                    validationErrors.push({ row: rowCount + 1, message: errorMessage, data: results.data });
                }
                parser.resume();
            },
            complete: async () => {
                // Process any remaining items in the last batch
                if (batch.length > 0) {
                    await processBatch(batch);
                }

                if (isDryRun) {
                    resolve({
                        processedCount: processedCount,
                        errorCount: validationErrors.length,
                        errors: validationErrors,
                        summaryMessage: validationErrors.length > 0
                          ? `[Dry Run] Found ${validationErrors.length} errors in ${rowCount} rows. No data was written.`
                          : `[Dry Run] This file is valid. Uncheck "Dry Run" to import ${processedCount} rows.`
                    });
                    return;
                }
                
                const hadErrors = validationErrors.length > 0;
                const summaryMessage = hadErrors
                    ? `Partial import complete. ${processedCount} rows imported, ${validationErrors.length} rows had errors.`
                    : `Import complete. ${processedCount} rows imported successfully.`;

                if (importId) {
                    await updateImportJob(importId, { processedCount, errorCount: validationErrors.length, errors: validationErrors, summaryMessage });
                }

                resolve({ importId, processedCount, errorCount: validationErrors.length, errors: validationErrors, summaryMessage });
            },
        });

        parser.on('error', (error: unknown) => {
            reject(new Error(getErrorMessage(error)));
        });
        
        fileContentStream.pipe(parser);
    });
}


export async function getMappingSuggestions(formData: FormData): Promise<CsvMappingOutput> {
    const file = formData.get('file') as File | null;
    if (!file) {
        throw new Error('File not provided for mapping suggestions.');
    }
    
    const fileContent = await file.text();
    const { data: rows, meta } = Papa.parse<Record<string, unknown>>(fileContent, {
        header: true,
        skipEmptyLines: true,
        preview: 5,
    });

    const csvHeaders = (meta.fields || []);
    
    const importType = formData.get('dataType') as string;
    const schemas = {
        'product-costs': ProductCostImportSchema,
        'suppliers': SupplierImportSchema,
        'historical-sales': HistoricalSalesImportSchema,
    };
    const schema = schemas[importType as keyof typeof schemas];
    if (!schema) throw new Error('Invalid data type for mapping.');

    const expectedDbFields = Object.keys(schema.shape);

    const result = await suggestCsvMappings({
        csvHeaders,
        sampleRows: rows,
        expectedDbFields
    });
    
    return result;
}


export async function handleDataImport(formData: FormData): Promise<ImportResult> {
    const isDryRun = formData.get('dryRun') === 'true';
    const mappingsStr = formData.get('mappings') as string | null;
    const mappings = mappingsStr ? JSON.parse(mappingsStr) : {};
    const file = formData.get('file') as File | null;
    const dataType = formData.get('dataType') as string;
    
    let importJobId: string | undefined;

    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        
        const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
        const { limited } = await rateLimit(ip, 'data_import', 10, 3600);
        if (limited) {
            return { success: false, isDryRun, summaryMessage: 'You have reached the import limit. Please try again in an hour.' };
        }

        await validateCSRF(formData);

        if (!file || file.size === 0) {
            return { success: false, isDryRun, summaryMessage: 'No file was uploaded or the file is empty.' };
        }
        if (file.size > MAX_FILE_SIZE_BYTES) {
            return { success: false, isDryRun, summaryMessage: `File size exceeds the ${MAX_FILE_SIZE_MB}MB limit.` };
        }
        
        let result: Omit<ImportResult, 'success' | 'isDryRun'>;
        let requiresViewRefresh = false;

        const importSchemas = {
            'product-costs': { schema: ProductCostImportSchema },
            'suppliers': { schema: SupplierImportSchema },
            'historical-sales': { schema: HistoricalSalesImportSchema },
        };

        const currentConfig = importSchemas[dataType as keyof typeof importSchemas];
        
        const approximateTotalRows = Math.floor(file.size / 150); // Estimate based on average row size
        importJobId = !isDryRun ? await createImportJob(companyId, userId, dataType, file.name, approximateTotalRows) : undefined;
        
        result = await processCsv(file.stream() as unknown as NodeJS.ReadableStream, currentConfig.schema, companyId, userId, isDryRun, mappings, dataType, importJobId);

        if (!isDryRun && (result.processedCount || 0) > 0) {
            await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
            requiresViewRefresh = true;
            revalidatePath('/inventory');
            revalidatePath('/suppliers');
            revalidatePath('/sales');
        }

        if (!isDryRun && requiresViewRefresh) {
            await refreshMaterializedViews(companyId);
        }

        return { success: true, isDryRun, ...result };

    } catch (error: unknown) {
        const errorMessage = getErrorMessage(error);
        logError(error, { context: 'handleDataImport action' });
        if (importJobId) {
            await failImportJob(importJobId, errorMessage);
        }
        return { success: false, isDryRun, summaryMessage: `An unexpected server error occurred: ${errorMessage}` };
    }
}
