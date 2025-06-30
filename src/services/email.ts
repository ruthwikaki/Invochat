
'use server';

/**
 * @fileoverview
 * This file contains a simulated email service for sending alerts and purchase orders.
 * In a production environment, this would be replaced with a real email
 * sending service like Resend, SendGrid, or Nodemailer.
 */

import type { Alert, PurchaseOrder } from '@/types';
import { logger } from '@/lib/logger';

/**
 * Simulates sending an email alert.
 * @param alert The alert object containing details for the email.
 */
export async function sendEmailAlert(alert: Alert): Promise<void> {
  logger.info('--- SIMULATING EMAIL ALERT ---');
  
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

    This is a simulated email. To enable real email sending, integrate a service here.
  `.trim();

  logger.info(`To: user@example.com`);
  logger.info(`Subject: ${subject}`);
  logger.info('Body:', `\n${body}`);
  logger.info('------------------------------');
}


/**
 * Simulates sending a purchase order email to a supplier.
 * @param po The purchase order object.
 */
export async function sendPurchaseOrderEmail(po: PurchaseOrder): Promise<void> {
    logger.info('--- SIMULATING PURCHASE ORDER EMAIL ---');

    const subject = `Purchase Order #${po.po_number} from Your Company`;
    const toEmail = po.supplier_email || 'supplier-not-found@example.com';

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
          Unit Cost: $${item.unit_cost.toFixed(2)}
        `;
    });

    body += `
        ------------------------------------------------------------
        Total Amount: $${po.total_amount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}

        Notes:
        ${po.notes || 'No notes provided.'}

        Thank you,
        Your Company
    `.trim();

    logger.info(`To: ${toEmail}`);
    logger.info(`Subject: ${subject}`);
    logger.info('Body:', `\n${body}`);
    logger.info('---------------------------------------');
}
