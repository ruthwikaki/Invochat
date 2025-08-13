
'use server';

import { getAuthContext } from '@/lib/auth-helpers';
import { revalidatePath } from 'next/cache';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { createPurchaseOrdersFromSuggestionsInDb } from '@/services/database';
import type { ReorderSuggestion } from '@/schemas/reorder';
import Papa from 'papaparse';
import { getReorderSuggestions as getReorderSuggestionsFlow } from '@/ai/flows/reorder-tool';

export async function getReorderReport(): Promise<ReorderSuggestion[]> {
    try {
        const { companyId } = await getAuthContext();
        // The getReorderSuggestions flow already returns the fully enhanced suggestion object
        return await getReorderSuggestionsFlow({ companyId }) as ReorderSuggestion[];
    } catch (error) {
        // Log the error for debugging but don't throw it
        logError(error, { context: 'getReorderReport failed' });
        
        // Return empty array instead of throwing error
        // This allows the UI to show the empty state
        return [];
    }
}

export async function createPurchaseOrdersFromSuggestions(suggestions: ReorderSuggestion[]): Promise<{ success: boolean; createdPoCount?: number; error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        const createdPoCount = await createPurchaseOrdersFromSuggestionsInDb(companyId, userId, suggestions);
        revalidatePath('/purchase-orders');
        revalidatePath('/analytics/reordering');
        return { success: true, createdPoCount };
    } catch (e) {
        logError(e, { context: 'createPurchaseOrdersFromSuggestions failed' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function exportReorderSuggestions(suggestions: ReorderSuggestion[]) {
    try {
        const dataToExport = suggestions.map(s => ({
            sku: s.sku,
            product_name: s.product_name,
            supplier_name: s.supplier_name,
            current_quantity: s.current_quantity,
            suggested_reorder_quantity: s.suggested_reorder_quantity,
            unit_cost: s.unit_cost !== null && s.unit_cost !== undefined ? (s.unit_cost / 100).toFixed(2) : '',
            total_cost: s.unit_cost !== null && s.unit_cost !== undefined ? ((s.suggested_reorder_quantity * s.unit_cost) / 100).toFixed(2) : '',
            adjustment_reason: s.adjustment_reason,
            confidence: s.confidence,
        }));
        const csv = Papa.unparse(dataToExport);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
