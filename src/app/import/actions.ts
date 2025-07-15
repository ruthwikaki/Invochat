
'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import Papa from 'papaparse';
import { z } from 'zod';
import { ProductCostImportSchema, SupplierImportSchema, HistoricalSalesImportSchema } from './schemas';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logger } from '@/lib/logger';
import { invalidateCompanyCache, rateLimit } from '@/lib/redis';
import { CSRF_FORM_NAME, validateCSRF } from '@/lib/csrf';
import { getErrorMessage, logError } from '@/lib/error-handler';
import type { User, CsvMappingInput, CsvMappingOutput } from '@/types';
import { revalidatePath } from 'next/cache';
import { refreshMaterializedViews } from '@/services/database';
import { suggestCsvMappings } from '@/ai/flows/csv-mapping-flow';

const MAX_FILE_SIZE_MB = 10;
const MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024;
const BATCH_SIZE = 500;

export type ImportResult = {
  success: boolean;
  isDryRun: boolean;
  importId?: string;
  processedCount?: number;
  errorCount?: number;
  errors?: { row: number; message: string; data: Record<string, any> }[];
  summary?: Record<string, any>;
  summaryMessage: string;
};


type UserRole = 'Owner' | 'Admin' | 'Member';

async function getAuthContextForImport(): Promise<{ user: User, companyId: string, userRole: UserRole }> {
  const cookieStore = cookies();
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: { get: (name: string) => cookieStore.get(name)?.value },
    }
  );
  const { data: { user } } = await supabase.auth.getUser();
  const companyId = user?.app_metadata?.company_id;
  const userRole = user?.app_metadata?.role as UserRole;
  if (!user || !companyId || !userRole) {
    throw new Error('Authentication error: User or company not found.');
  }
  return { user, companyId, userRole };
}

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
    await supabase.from('imports').update({
        processed_rows: updates.processedCount,
        failed_rows: updates.errorCount,
        errors: updates.errors,
        summary: updates.summary,
        status: (updates.errorCount ?? 0) > 0 ? 'completed_with_errors' : 'completed',
        completed_at: new Date().toISOString()
    }).eq('id', importId);
}


async function processCsv<T extends z.ZodType>(
    fileContentStream: NodeJS.ReadableStream,
    schema: T,
    tableName: string,
    companyId: string,
    userId: string,
    isDryRun: boolean,
    mappings: Record<string, string>,
    importType: string,
    importId?: string
): Promise<Omit<ImportResult, 'success' | 'isDryRun'>> {
    
    return new Promise((resolve, reject) => {
        const validRows: z.infer<T>[] = [];
        const validationErrors: { row: number; message: string; data: Record<string, any> }[] = [];
        let rowCount = 0;
        
        const parser = Papa.parse(Papa.NODE_STREAM_INPUT, {
            header: true,
            skipEmptyLines: true,
            transformHeader: header => header.trim().toLowerCase(),
            step: async (results, parser) => {
                rowCount++;
                if (rowCount > 10000) {
                    parser.abort();
                    return reject(new Error('File exceeds the maximum of 10,000 rows per import.'));
                }

                let row = results.data as Record<string, any>;
                if (mappings && Object.keys(mappings).length > 0) {
                    const newRow: Record<string, any> = {};
                    for (const originalHeader in row) {
                        if (mappings[originalHeader]) {
                            newRow[mappings[originalHeader]] = row[originalHeader];
                        }
                    }
                    row = newRow;
                }

                row.company_id = companyId;
                const result = schema.safeParse(row);

                if (result.success) {
                    validRows.push(result.data);
                } else {
                    const errorMessage = result.error.issues.map(issue => `${issue.path.join('.')}: ${issue.message}`).join(', ');
                    validationErrors.push({ row: rowCount + 1, message: errorMessage, data: results.data });
                }
            },
            complete: async () => {
                if (isDryRun) {
                    return resolve({
                        processedCount: validRows.length,
                        errorCount: validationErrors.length,
                        errors: validationErrors,
                        summaryMessage: validationErrors.length > 0
                          ? `[Dry Run] Found ${validationErrors.length} errors in ${rowCount} rows. No data was written.`
                          : `[Dry Run] This file is valid. Uncheck "Dry Run" to import ${validRows.length} rows.`
                    });
                }
                
                let processedCount = 0;
                if (validRows.length > 0) {
                    const supabase = getServiceRoleClient();
                    if (!supabase) return reject(new Error('Supabase admin client not initialized.'));

                    const rpcMap = { 'product-costs': 'batch_upsert_costs', 'suppliers': 'batch_upsert_suppliers', 'historical-sales': 'batch_import_sales' };
                    const rpcToCall = rpcMap[importType as keyof typeof rpcMap];
                    if (!rpcToCall) return reject(new Error(`Unsupported import type for batch processing: ${importType}`));

                    for (let i = 0; i < validRows.length; i += BATCH_SIZE) {
                        const batch = validRows.slice(i, i + BATCH_SIZE);
                        const { error: dbError } = await supabase.rpc(rpcToCall, { p_records: batch, p_company_id: companyId, p_user_id: userId });
                        if (dbError) {
                            logError(dbError, { context: `Transactional database error for ${importType}` });
                            validationErrors.push({ row: 0, message: `Database error during batch import: ${dbError.message}`, data: {} });
                        } else {
                            processedCount += batch.length;
                        }
                    }
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
            error: (error) => reject(error)
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

    try {
        const { user, companyId, userRole } = await getAuthContextForImport();
        
        if (userRole !== 'Owner' && userRole !== 'Admin') {
            return { success: false, isDryRun, summaryMessage: 'You do not have permission to import data.' };
        }
        
        const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
        const { limited } = await rateLimit(ip, 'data_import', 10, 3600);
        if (limited) {
            return { success: false, isDryRun, summaryMessage: 'You have reached the import limit. Please try again in an hour.' };
        }

        validateCSRF(formData);

        const file = formData.get('file') as File | null;
        const dataType = formData.get('dataType') as string;
        
        if (!file || file.size === 0) {
            return { success: false, isDryRun, summaryMessage: 'No file was uploaded or the file is empty.' };
        }
        if (file.size > MAX_FILE_SIZE_BYTES) {
            return { success: false, isDryRun, summaryMessage: `File size exceeds the ${MAX_FILE_SIZE_MB}MB limit.` };
        }
        
        let result: Omit<ImportResult, 'success' | 'isDryRun'>;
        let requiresViewRefresh = false;

        const importSchemas = {
            'product-costs': { schema: ProductCostImportSchema, tableName: 'inventory' },
            'suppliers': { schema: SupplierImportSchema, tableName: 'suppliers' },
            'historical-sales': { schema: HistoricalSalesImportSchema, tableName: 'sales' },
        };

        const config = importSchemas[dataType as keyof typeof importSchemas];
        if (!config) {
            throw new Error(`Unsupported data type: ${dataType}`);
        }
        
        // This is a temporary solution for getting total rows. A full streaming solution would not know this upfront.
        const totalRows = (await file.text()).split('\n').length -1;
        const importJobId = !isDryRun ? await createImportJob(companyId, user.id, dataType, file.name, totalRows) : undefined;
        
        result = await processCsv(file.stream() as any, config.schema, config.tableName, companyId, user.id, isDryRun, mappings, dataType, importJobId);

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

    } catch (error) {
        logError(error, { context: 'handleDataImport action' });
        return { success: false, isDryRun, summaryMessage: `An unexpected server error occurred: ${getErrorMessage(error)}` };
    }
}
