'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import Papa from 'papaparse';
import { z } from 'zod';
import { InventoryImportSchema, SupplierImportSchema, SupplierCatalogImportSchema, ReorderRuleImportSchema, LocationImportSchema } from './schemas';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { logger } from '@/lib/logger';
import { invalidateCompanyCache, rateLimit } from '@/lib/redis';
import { validateCSRF, CSRF_COOKIE_NAME, CSRF_FORM_NAME } from '@/lib/csrf';
import { getErrorMessage, logError } from '@/lib/error-handler';
import type { User } from '@/types';
import { revalidatePath } from 'next/cache';
import { refreshMaterializedViews } from '@/services/database';
import { suggestCsvMappings, type CsvMappingOutput } from '@/ai/flows/csv-mapping-flow';

const MAX_FILE_SIZE_MB = 10;
const MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024;
// Lenient check as MIME types can be inconsistent across browsers/OS
const ALLOWED_MIME_TYPES = ['text/csv', 'application/vnd.ms-excel', 'text/plain'];

// Define a type for the structure of our import results.
export type ImportResult = {
  success: boolean;
  isDryRun: boolean;
  processedCount?: number;
  errorCount?: number;
  errors?: { row: number; message: string }[];
  summaryMessage: string;
};

type UserRole = 'Owner' | 'Admin' | 'Member';

// A helper function to get the current user's company ID.
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

// A generic function to process any CSV file with a given schema and table name.
async function processCsv<T extends z.ZodType>(
    fileContent: string,
    schema: T,
    tableName: string,
    companyId: string,
    isDryRun: boolean
): Promise<Omit<ImportResult, 'success' | 'isDryRun'>> {
    const { data: rows, errors: parsingErrors } = Papa.parse<Record<string, unknown>>(fileContent, {
        header: true,
        skipEmptyLines: true,
        transformHeader: header => header.trim(),
    });

    const validationErrors: { row: number; message: string }[] = [];

    // Add parsing errors to the list of validation errors
    if (parsingErrors.length > 0) {
        parsingErrors.forEach(e => validationErrors.push({ row: e.row, message: e.message }));
    }

    const validRows: z.infer<T>[] = [];

    for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        // Securely inject the company_id before validation.
        row.company_id = companyId;

        const result = schema.safeParse(row);

        if (result.success) {
            validRows.push(result.data);
        } else {
            const errorMessage = result.error.issues.map(issue => `${issue.path.join('.')}: ${issue.message}`).join(', ');
            validationErrors.push({ row: i + 2, message: errorMessage }); // +2 because of header and 0-indexing
        }
    }

    if (isDryRun) {
        return {
            processedCount: validRows.length,
            errorCount: validationErrors.length,
            errors: validationErrors,
            summaryMessage: validationErrors.length > 0
              ? `[Dry Run] Found ${validationErrors.length} errors in ${rows.length} rows. No data was written.`
              : `[Dry Run] This file is valid. Uncheck "Dry Run" to import ${validRows.length} rows.`
        };
    }

    let processedCount = 0;

    if (validRows.length > 0) {
        const supabase = supabaseAdmin;
        if (!supabase) throw new Error('Supabase admin client not initialized.');

        // Define what makes a row unique for upserting.
        let conflictTarget: string[] = [];
        if (tableName === 'inventory') conflictTarget = ['company_id', 'sku'];
        if (tableName === 'vendors') conflictTarget = ['company_id', 'vendor_name'];
        if (tableName === 'supplier_catalogs') conflictTarget = ['supplier_id', 'sku'];
        if (tableName === 'reorder_rules') conflictTarget = ['company_id', 'sku'];
        if (tableName === 'locations') conflictTarget = ['company_id', 'name'];


        // Use a transactional RPC to ensure all-or-nothing import.
        const { error: dbError } = await supabase.rpc('batch_upsert_with_transaction', {
            p_table_name: tableName,
            p_records: validRows,
            p_conflict_columns: conflictTarget,
        });

        if (dbError) {
            logError(dbError, { context: `Transactional database error for ${tableName}` });
            const errorMessage = dbError.message.includes('unique constraint') 
              ? `Database error: A row in your CSV has a value that must be unique but already exists (e.g., a duplicate SKU or name). ${dbError.message}`
              : `Database error: ${dbError.message}. The import was rolled back.`;
              
            return {
                processedCount: 0,
                errorCount: rows.length,
                errors: [{ row: 0, message: errorMessage }],
                summaryMessage: 'A database error occurred during import. No data was saved.'
            };
        }
        processedCount = validRows.length;
    }
    
    const hadErrors = validationErrors.length > 0;
    const summaryMessage = hadErrors
        ? `Partial import complete. ${processedCount} rows imported, ${validationErrors.length} rows had errors.`
        : `Import complete. ${processedCount} rows imported successfully.`;

    return {
        processedCount,
        errorCount: validationErrors.length,
        errors: validationErrors,
        summaryMessage: summaryMessage
    };
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
        preview: 5, // Use first 5 rows as a sample
    });

    const csvHeaders = (meta.fields || []);
    
    // This is a placeholder for getting the DB fields based on import type
    const expectedDbFields = ['sku', 'name', 'quantity', 'cost', 'category', 'supplier_name', 'location'];

    const result = await suggestCsvMappings({
        csvHeaders,
        sampleRows: rows,
        expectedDbFields
    });
    
    return result;
}


// The main server action that the client calls.
export async function handleDataImport(formData: FormData): Promise<ImportResult> {
    const isDryRun = formData.get('dryRun') === 'true';
    try {
        const { user, companyId, userRole } = await getAuthContextForImport();
        
        if (userRole !== 'Owner' && userRole !== 'Admin') {
            return { success: false, isDryRun, summaryMessage: 'You do not have permission to import data.' };
        }
        
        const { limited } = await rateLimit(user.id, 'data_import', 10, 3600);
        if (limited) {
            return { success: false, isDryRun, summaryMessage: 'You have reached the import limit. Please try again in an hour.' };
        }

        const cookieStore = cookies();
        const csrfTokenFromCookie = cookieStore.get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);

        const file = formData.get('file') as File | null;
        const dataType = formData.get('dataType') as string;
        
        if (!file || file.size === 0) {
            return { success: false, isDryRun, summaryMessage: 'No file was uploaded or the file is empty.' };
        }

        if (file.size > MAX_FILE_SIZE_BYTES) {
            return { success: false, isDryRun, summaryMessage: `File size exceeds the ${MAX_FILE_SIZE_MB}MB limit.` };
        }
        
        if (!ALLOWED_MIME_TYPES.includes(file.type)) {
            logger.warn(`[Data Import] Blocked invalid file type: ${file.type}`);
            return { success: false, isDryRun, summaryMessage: `Invalid file type. Only CSV files are allowed.` };
        }
        
        const fileContent = await file.text();
        let result: Omit<ImportResult, 'success' | 'isDryRun'>;
        let requiresViewRefresh = false;

        switch (dataType) {
            case 'inventory':
                result = await processCsv(fileContent, InventoryImportSchema, 'inventory', companyId, isDryRun);
                if (!isDryRun && (result.processedCount || 0) > 0) {
                    await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
                    requiresViewRefresh = true;
                    revalidatePath('/inventory');
                }
                break;
            case 'suppliers':
                result = await processCsv(fileContent, SupplierImportSchema, 'vendors', companyId, isDryRun);
                if (!isDryRun && (result.processedCount || 0) > 0) {
                    await invalidateCompanyCache(companyId, ['suppliers']);
                    revalidatePath('/suppliers');
                }
                break;
            case 'supplier_catalogs':
                result = await processCsv(fileContent, SupplierCatalogImportSchema, 'supplier_catalogs', companyId, isDryRun);
                break;
            case 'reorder_rules':
                result = await processCsv(fileContent, ReorderRuleImportSchema, 'reorder_rules', companyId, isDryRun);
                if (!isDryRun && (result.processedCount || 0) > 0) revalidatePath('/reordering');
                break;
            case 'locations':
                result = await processCsv(fileContent, LocationImportSchema, 'locations', companyId, isDryRun);
                if (!isDryRun && (result.processedCount || 0) > 0) revalidatePath('/locations');
                break;
            default:
                throw new Error(`Unsupported data type: ${dataType}`);
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
