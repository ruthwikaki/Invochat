
'use server';

import { pdf } from '@react-pdf/renderer';
import type { ReactElement } from 'react';
import { createAuditLogInDb } from '@/services/database';
import { PurchaseOrderPDF } from '@/components/pdf/purchase-order-pdf';
import type { ReorderSuggestion, CompanyInfo, PurchaseOrderWithItems } from '@/types';

interface GeneratePOPdfProps {
    purchaseOrder: PurchaseOrderWithItems & { notes?: string | null };
    companyInfo: CompanyInfo & { 
        address?: string | null;
        phone?: string | null;
        email?: string | null;
    };
    supplierName: string;
    supplierInfo: {
        email: string | null;
        phone: string | null;
        notes: string | null;
    };
    companyId: string;
    userId: string;
}

export async function generatePOPdf({ 
    purchaseOrder, 
    companyInfo, 
    supplierName, 
    supplierInfo, 
    companyId, 
    userId 
}: GeneratePOPdfProps): Promise<Uint8Array> {
    try {
        // Convert to PDF buffer using the PDF component  
        const pdfBlob = await pdf(
            PurchaseOrderPDF({
                purchaseOrder,
                companyInfo,
                supplierName,
                supplierInfo
            }) as ReactElement
        ).toBlob();

        // Convert Blob to ArrayBuffer and then to Uint8Array
        const arrayBuffer = await pdfBlob.arrayBuffer();

        // Create audit log
        await createAuditLogInDb(companyId, userId, 'purchase_order_pdf_generated', {
            po_id: purchaseOrder.id,
            po_number: `PO-${purchaseOrder.id}`,
            supplier_name: supplierName,
            item_count: purchaseOrder.line_items?.length || 0,
            total_amount: purchaseOrder.total_cost || 0,
        });

        return new Uint8Array(arrayBuffer);
    } catch (error) {
        console.error('PDF generation failed:', error);
        
        // Create error audit log
        await createAuditLogInDb(companyId, userId, 'purchase_order_pdf_error', {
            po_id: purchaseOrder.id,
            error: error instanceof Error ? error.message : 'Unknown error',
        });

        throw new Error('Failed to generate PDF: ' + (error instanceof Error ? error.message : 'Unknown error'));
    }
}

// Legacy interface support for reorder suggestions
interface LegacyGeneratePOPdfProps {
    supplierName: string;
    supplierInfo: {
        email: string | null;
        phone: string | null;
        notes: string | null;
    };
    items: ReorderSuggestion[];
    companyId: string;
    userId: string;
    companyInfo: CompanyInfo & { 
        address?: string | null;
        phone?: string | null;
        email?: string | null;
    };
}

export async function generatePOPdfFromReorderSuggestions({ 
    supplierName, 
    supplierInfo,
    items, 
    companyId, 
    userId,
    companyInfo 
}: LegacyGeneratePOPdfProps) {
    const poNumber = `PO-${Date.now()}`;
    
    // Convert reorder suggestions to purchase order format
    const mockPurchaseOrder: PurchaseOrderWithItems & { notes?: string | null } = {
        id: poNumber,
        company_id: companyId,
        supplier_id: 'temp',
        status: 'Draft',
        po_number: poNumber,
        total_cost: items.reduce((sum, item) => sum + (item.unit_cost || 0) * (item.suggested_reorder_quantity || 0), 0),
        notes: 'Generated from reorder suggestions',
        created_at: new Date().toISOString(),
        expected_arrival_date: null,
        idempotency_key: null,
        line_items: items.map(item => ({
            id: `temp-${item.product_id}`,
            purchase_order_id: poNumber,
            product_id: item.product_id,
            product_name: item.product_name,
            sku: item.sku,
            quantity: item.suggested_reorder_quantity || 0,
            cost: item.unit_cost || 0,
        })),
    };

    return generatePOPdf({
        purchaseOrder: mockPurchaseOrder,
        companyInfo,
        supplierName,
        supplierInfo,
        companyId,
        userId,
    });
}
