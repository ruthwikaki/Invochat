'use server';

import { generatePOPdf } from '@/lib/pdf-generator';
import { getPurchaseOrderByIdFromDB } from '@/services/database';
import { getAuthContext } from '@/lib/auth-helpers';

interface GeneratePDFActionProps {
    purchaseOrderId: string;
    supplierName: string;
    supplierInfo: {
        email: string | null;
        phone: string | null;
        notes: string | null;
    };
}

export async function generatePurchaseOrderPDF(props: GeneratePDFActionProps) {
    try {
        const authContext = await getAuthContext();
        
        // Get purchase order details
        const purchaseOrder = await getPurchaseOrderByIdFromDB(props.purchaseOrderId, authContext.companyId);
        
        if (!purchaseOrder) {
            return { success: false, error: 'Purchase order not found' };
        }

        // Get company information - for now use basic info
        const companyInfo = {
            id: authContext.companyId,
            name: 'Your Company',
            address: null,
            phone: null,
            email: null,
        };

        // Generate PDF
        const pdfBuffer = await generatePOPdf({
            purchaseOrder: purchaseOrder as any,
            companyInfo,
            supplierName: props.supplierName,
            supplierInfo: props.supplierInfo,
            companyId: authContext.companyId,
            userId: authContext.userId,
        });

        // Convert Uint8Array to base64 for client transmission
        const base64String = Buffer.from(pdfBuffer).toString('base64');

        return { 
            success: true, 
            pdf: base64String,
            filename: `PO-${purchaseOrder.id}-${new Date().toISOString().split('T')[0]}.pdf`
        };
    } catch (error) {
        console.error('PDF generation failed:', error);
        return { 
            success: false, 
            error: error instanceof Error ? error.message : 'Failed to generate PDF' 
        };
    }
}
