
'use server';

import { getAuthContext } from '@/lib/auth-helpers';
import { revalidatePath } from 'next/cache';
import { getErrorMessage } from '@/lib/error-handler';
import { createPurchaseOrdersInDb, createAuditLogInDb } from '@/services/database';
import type { ReorderSuggestion } from '@/types';
import { validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { getReorderSuggestions as getReorderSuggestionsTool } from '@/ai/flows/reorder-tool';


export async function getReorderReport() {
    const { companyId } = await getAuthContext();
    return getReorderSuggestionsTool.func({ companyId });
}

export async function createPurchaseOrdersFromSuggestions(formData: FormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await validateCSRF(formData);
        const suggestions = JSON.parse(formData.get('suggestions') as string) as ReorderSuggestion[];
        const result = await createPurchaseOrdersInDb(companyId, userId, suggestions);
        
        await createAuditLogInDb(companyId, userId, 'ai_purchase_order_created', {
            createdPoCount: result,
            totalSuggestions: suggestions.length,
            sampleSkus: suggestions.slice(0, 5).map(s => s.sku),
        });

        revalidatePath('/purchase-orders');
        revalidatePath('/analytics/reordering');
        return { success: true, createdPoCount: result };
    } catch (e) {
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
