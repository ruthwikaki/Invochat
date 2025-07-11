
'use server';

/**
 * @fileoverview
 * This file contains the email service for sending alerts and purchase orders.
 * It uses the Resend email platform.
 */

import type { Alert, PurchaseOrder } from '@/types';
import { logger } from '@/lib/logger';
import { Resend } from 'resend';

// Initialize Resend with the API key from environment variables.
// The key is checked at startup, but we add a fallback for safety.
const resend = new Resend(process.env.RESEND_API_KEY);
const fromEmail = process.env.EMAIL_FROM || 'onboarding@resend.dev';


/**
 * Sends an email alert.
 * @param alert The alert object containing details for the email.
 */
export async function sendEmailAlert(alert: Alert): Promise<void> {
  const subject = `InvoChat Alert: ${alert.title} - ${alert.metadata.productName || 'System Alert'}`;
  
  const body = `
    A new alert has been triggered in your InvoChat account.

    Alert Type: ${alert.type.replace(/_/g, ' ')}
    Severity: ${alert.severity.toUpperCase()}
    Title: ${alert.title}
    Message: ${alert.message}

    Details:
    - Product: ${alert.metadata.productName || 'N/A'}
    - SKU: ${alert.metadata.productId ? `(ID: ${alert.metadata.productId})` : 'N/A'}
    - Current Stock: ${alert.metadata.currentStock ?? 'N/A'}
    - Reorder Point: ${alert.metadata.reorderPoint ?? 'N/A'}
    - Last Sold Date: ${alert.metadata.lastSoldDate ? new Date(alert.metadata.lastSoldDate).toLocaleDateString() : 'N/A'}
    - Current Value: $${alert.metadata.value?.toLocaleString() || 'N/A'}

    You can view this alert in your InvoChat dashboard.
  `.trim();

  try {
    await resend.emails.send({
        from: fromEmail,
        to: 'user@example.com', // In a real app, this would be the user's email
        subject: subject,
        text: body,
    });
    logger.info(`Successfully sent email alert for: ${alert.title}`);
  } catch (error) {
    logger.error('Failed to send email alert via Resend:', error);
    // In a production app, you might want to add this to a retry queue.
  }
}


/**
 * Sends a purchase order email to a supplier.
 * @param po The purchase order object.
 */
export async function sendPurchaseOrderEmail(po: PurchaseOrder): Promise<void> {
    const toEmail = po.supplier_email || null;
    if (!toEmail) {
        logger.warn(`Cannot send PO email for PO #${po.po_number} because supplier email is missing.`);
        return;
    }
    
    const subject = `Purchase Order #${po.po_number} from Your Company`;

    let body = `
        Hello ${po.supplier_name},

        Please find our Purchase Order #${po.po_number} attached.

        Order Date: ${new Date(po.order_date).toLocaleDateString()}
        Expected Delivery Date: ${po.expected_date ? new Date(po.expected_date).toLocaleDateString() : 'N/A'}

        Items Requested:
        ------------------------------------------------------------
    `.trim();

    po.items?.forEach(item => {
        body += `
        - SKU: ${item.sku}
          Product: ${item.product_name || 'N/A'}
          Quantity: ${item.quantity_ordered}
          Unit Cost: $${(item.unit_cost / 100).toFixed(2)}
        `;
    });

    body += `
        ------------------------------------------------------------
        Total Amount: $${(po.total_amount / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}

        Notes:
        ${po.notes || 'No notes provided.'}

        Thank you,
        Your Company
    `.trim();

    try {
         await resend.emails.send({
            from: fromEmail,
            to: toEmail,
            subject: subject,
            text: body,
        });
        logger.info(`Successfully sent PO #${po.po_number} to ${toEmail}`);
    } catch(error) {
        logger.error(`Failed to send PO email to ${toEmail} via Resend:`, error);
    }
}

// TODO: Add functions for other email types like password reset, welcome, etc.
