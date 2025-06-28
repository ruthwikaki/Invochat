
'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import Papa from 'papaparse';
import { z } from 'zod';
import { InventoryImportSchema, SupplierImportSchema } from './schemas';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { logger } from '@/lib/logger';
import { invalidateCompanyCache } from '@/lib/redis';

// Define a type for the structure of our import results.
export type ImportResult = {
  successCount: number;
  errorCount: number;
  errors: { row: number; message: string }[];
  summaryMessage: string;
};

// A helper function to get the current user's company ID.
async function getCompanyIdForCurrentUser(): Promise<string> {
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
  if (!user || !companyId) {
    throw new Error('Authentication error: User or company not found.');
  }
  return companyId;
}

// A generic function to process any CSV file with a given schema and table name.
async function processCsv<T extends z.ZodType<any, any>>(
    fileContent: string,
    schema: T,
    tableName: string,
    companyId: string
): Promise<ImportResult> {
    const { data: rows, errors: parsingErrors } = Papa.parse(fileContent, {
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
        const row = rows[i] as any;
        const result = schema.safeParse(row);

        if (result.success) {
            validRows.push({ ...result.data, company_id: companyId });
        } else {
            const errorMessage = result.error.issues.map(issue => `${issue.path.join('.')}: ${issue.message}`).join(', ');
            validationErrors.push({ row: i + 2, message: errorMessage }); // +2 because of header and 0-indexing
        }
    }

    if (validRows.length > 0) {
        const supabase = supabaseAdmin;
        if (!supabase) throw new Error('Supabase admin client not initialized.');

        // Use upsert to either insert new data or update existing data based on a conflict target.
        // This is safer than a simple insert. We need to define what makes a row unique.
        let conflictTarget: string[] = [];
        if (tableName === 'inventory_valuation') conflictTarget = ['company_id', 'sku'];
        if (tableName === 'vendors') conflictTarget = ['company_id', 'vendor_name'];

        const { error: dbError } = await supabase
            .from(tableName)
            .upsert(validRows, { onConflict: conflictTarget.join(',') });

        if (dbError) {
            logger.error(`[Data Import] Database error for ${tableName}:`, dbError);
            return {
                successCount: 0,
                errorCount: rows.length,
                errors: [{ row: 0, message: `Database error: ${dbError.message}. Check for conflicts or data type mismatches.` }],
                summaryMessage: 'A database error occurred during import.'
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


// The main server action that the client calls.
export async function handleDataImport(formData: FormData): Promise<ImportResult> {
    try {
        const file = formData.get('file') as File | null;
        const dataType = formData.get('dataType') as string;
        
        if (!file || file.size === 0) {
            return { successCount: 0, errorCount: 0, errors: [{ row: 0, message: 'No file was uploaded or file is empty.' }], summaryMessage: 'Upload failed.' };
        }
        
        const fileContent = await file.text();
        const companyId = await getCompanyIdForCurrentUser();

        let result: ImportResult;

        switch (dataType) {
            case 'inventory':
                result = await processCsv(fileContent, InventoryImportSchema, 'inventory_valuation', companyId);
                if (result.successCount > 0) await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
                break;
            case 'suppliers':
                result = await processCsv(fileContent, SupplierImportSchema, 'vendors', companyId);
                if (result.successCount > 0) await invalidateCompanyCache(companyId, ['suppliers']);
                break;
            default:
                throw new Error(`Unsupported data type: ${dataType}`);
        }

        return result;

    } catch (e: any) {
        logger.error('[Data Import] An unexpected error occurred:', e);
        return { successCount: 0, errorCount: 0, errors: [{ row: 0, message: e.message }], summaryMessage: 'An unexpected server error occurred.' };
    }
}
