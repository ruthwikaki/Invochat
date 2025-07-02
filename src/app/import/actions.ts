
'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import Papa from 'papaparse';
import { z } from 'zod';
import { InventoryImportSchema, SupplierImportSchema, SupplierCatalogImportSchema, ReorderRuleImportSchema, LocationImportSchema } from './schemas';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { logger } from '@/lib/logger';
import { invalidateCompanyCache, rateLimit } from '@/lib/redis';
import { validateCSRFToken, CSRF_COOKIE_NAME, CSRF_HEADER_NAME } from '@/lib/csrf';
import { getErrorMessage, logError } from '@/lib/error-handler';
import type { User } from '@/types';
import { revalidatePath } from 'next/cache';
import { refreshMaterializedViews } from '@/services/database';

const MAX_FILE_SIZE_MB = 10;
const MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024;
const ALLOWED_MIME_TYPES = ['text/csv', 'application/vnd.ms-excel', 'text/plain'];

export type ImportResult = {
  success: boolean;
  successCount?: number;
  errorCount?: number;
  errors?: { row: number; message: string }[];
  summaryMessage: string;
};

type UserRole = 'Owner' | 'Admin' | 'Member';

async function getAuthContextForImport(): Promise<{ user: User, companyId: string, userRole: UserRole }> {
  const cookieStore = cookies();
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { get: (name: string) => cookieStore.get(name)?.value }, }
  );
  const { data: { user } } = await supabase.auth.getUser();
  const companyId = user?.app_metadata?.company_id;
  const userRole = user?.app_metadata?.role as UserRole;
  if (!user || !companyId || !userRole) {
    throw new Error('Authentication error: User or company not found.');
  }
  return { user, companyId, userRole };
}

async function processCsv<T extends z.ZodType>(
    fileContent: string,
    schema: T,
    tableName: string,
    companyId: string
): Promise<Omit<ImportResult, 'success'>> {
    const { data: rows, errors: parsingErrors } = Papa.parse<Record<string, unknown>>(fileContent, {
        header: true,
        skipEmptyLines: true,
        transformHeader: header => header.trim(),
    });

    if (parsingErrors.length > 0) {
        return { 
            successCount: 0, 
            errorCount: rows.length, 
            errors: parsingErrors.map(e => ({ row: e.row, message: e.message })),
            summaryMessage: 'Failed to parse CSV file. Please check the file format.'
        };
    }

    const validationErrors: { row: number; message: string }[] = [];
    const validRows: z.infer<T>[] = [];

    for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        row.company_id = companyId;
        const result = schema.safeParse(row);
        if (result.success) {
            validRows.push(result.data);
        } else {
            const errorMessage = result.error.issues.map(issue => `${issue.path.join('.')}: ${issue.message}`).join(', ');
            validationErrors.push({ row: i + 2, message: errorMessage });
        }
    }

    if (validRows.length > 0) {
        const supabase = supabaseAdmin;
        if (!supabase) throw new Error('Supabase admin client not initialized.');

        let conflictTarget: string[] = [];
        if (tableName === 'inventory') conflictTarget = ['company_id', 'sku'];
        if (tableName === 'vendors') conflictTarget = ['company_id', 'vendor_name'];
        if (tableName === 'supplier_catalogs') conflictTarget = ['supplier_id', 'sku'];
        if (tableName === 'reorder_rules') conflictTarget = ['company_id', 'sku'];
        if (tableName === 'locations') conflictTarget = ['company_id', 'name'];

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
                successCount: 0,
                errorCount: rows.length,
                errors: [{ row: 0, message: errorMessage }],
                summaryMessage: 'A database error occurred during import. No data was saved.'
            };
        }
    }

    return {
        successCount: validRows.length,
        errorCount: validationErrors.length,
        errors: validationErrors,
        summaryMessage: `Import complete. ${validRows.length} rows imported successfully, ${validationErrors.length} rows had errors.`
    };
}

function validateCsrf() {
    const tokenFromHeader = headers().get(CSRF_HEADER_NAME);
    const tokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;

    if (!validateCSRFToken(tokenFromHeader, tokenFromCookie)) {
        logger.warn(`[CSRF] Invalid token for data import. Action rejected.`);
        throw new Error('Invalid form submission. Please refresh the page and try again.');
    }
}

export async function handleDataImport(formData: FormData): Promise<ImportResult> {
    try {
        const { user, companyId, userRole } = await getAuthContextForImport();
        
        if (userRole !== 'Owner' && userRole !== 'Admin') {
            return { success: false, summaryMessage: 'You do not have permission to import data.' };
        }
        
        const { limited } = await rateLimit(user.id, 'data_import', 10, 3600);
        if (limited) {
            return { success: false, summaryMessage: 'You have reached the import limit. Please try again in an hour.' };
        }
        
        validateCsrf();

        const file = formData.get('file') as File | null;
        const dataType = formData.get('dataType') as string;
        
        if (!file || file.size === 0) {
            return { success: false, summaryMessage: 'No file was uploaded or the file is empty.' };
        }

        if (file.size > MAX_FILE_SIZE_BYTES) {
            return { success: false, summaryMessage: `File size exceeds the ${MAX_FILE_SIZE_MB}MB limit.` };
        }
        
        if (!ALLOWED_MIME_TYPES.includes(file.type)) {
            logger.warn(`[Data Import] Blocked invalid file type: ${file.type}`);
            return { success: false, summaryMessage: `Invalid file type. Only CSV files are allowed.` };
        }
        
        const fileContent = await file.text();
        let result: Omit<ImportResult, 'success'>;
        let requiresViewRefresh = false;

        switch (dataType) {
            case 'inventory':
                result = await processCsv(fileContent, InventoryImportSchema, 'inventory', companyId);
                if ((result.successCount || 0) > 0) {
                    await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
                    requiresViewRefresh = true;
                    revalidatePath('/inventory');
                }
                break;
            case 'suppliers':
                result = await processCsv(fileContent, SupplierImportSchema, 'vendors', companyId);
                if ((result.successCount || 0) > 0) {
                    await invalidateCompanyCache(companyId, ['suppliers']);
                    revalidatePath('/suppliers');
                }
                break;
            case 'supplier_catalogs':
                result = await processCsv(fileContent, SupplierCatalogImportSchema, 'supplier_catalogs', companyId);
                break;
            case 'reorder_rules':
                result = await processCsv(fileContent, ReorderRuleImportSchema, 'reorder_rules', companyId);
                if ((result.successCount || 0) > 0) revalidatePath('/reordering');
                break;
            case 'locations':
                result = await processCsv(fileContent, LocationImportSchema, 'locations', companyId);
                if ((result.successCount || 0) > 0) revalidatePath('/locations');
                break;
            default:
                throw new Error(`Unsupported data type: ${dataType}`);
        }

        if (requiresViewRefresh) {
            await refreshMaterializedViews(companyId);
        }

        return { success: true, ...result };

    } catch (error) {
        logError(error, { context: 'handleDataImport action' });
        return { success: false, summaryMessage: `An unexpected server error occurred: ${getErrorMessage(error)}` };
    }
}
