
'use server';

import { getAuthContext } from '@/lib/auth-helpers';
import { revalidatePath } from 'next/cache';
import { getErrorMessage } from '@/lib/error-handler';
import { createPurchaseOrdersInDb, createAuditLogInDb } from '@/services/database';
import type { ReorderSuggestion } from '@/types';
import { validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { getReorderSuggestions } from '@/ai/flows/reorder-tool';


export async function getReorderReport() {
    const { companyId } = await getAuthContext();
    return getReorderSuggestions({ companyId });
}

export async function createPurchaseOrdersFromSuggestions(formData: FormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await validateCSRF(formData);
        const allSuggestions = JSON.parse(formData.get('suggestions') as string) as ReorderSuggestion[];
        
        // Separate suggestions based on whether they have a supplier
        const suggestionsWithSupplier = allSuggestions.filter(s => s.supplier_id);
        
        if (suggestionsWithSupplier.length === 0) {
            return { success: false, error: "No items with an assigned supplier were selected. Please assign suppliers to products before creating a purchase order." };
        }

        const result = await createPurchaseOrdersInDb(companyId, userId, suggestionsWithSupplier);
        
        await createAuditLogInDb(companyId, userId, 'ai_purchase_order_created', {
            createdPoCount: result,
            totalSuggestions: suggestionsWithSupplier.length,
            sampleSkus: suggestionsWithSupplier.slice(0, 5).map(s => s.sku),
        });

        revalidatePath('/purchase-orders');
        revalidatePath('/analytics/reordering');
        
        const itemsWithoutSupplierCount = allSuggestions.length - suggestionsWithSupplier.length;
        let message = `${result} new PO(s) have been generated.`;
        if (itemsWithoutSupplierCount > 0) {
            message += ` ${itemsWithoutSupplierCount} item(s) were skipped because they are missing a supplier.`;
        }

        return { success: true, createdPoCount: result, message: message };
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
