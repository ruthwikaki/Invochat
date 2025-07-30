
'use server';

/**
 * @fileoverview
 * This file contains the email service for sending transactional and notification emails.
 * It uses the Resend email platform.
 */

import type { Alert, Anomaly } from '@/types';
import { logger } from '@/lib/logger';
import { Resend } from 'resend';
import { config } from '@/config/app-config';

// Initialize Resend with the API key from environment variables.
const resendApiKey = process.env.RESEND_API_KEY;
const resend = resendApiKey ? new Resend(resendApiKey) : null;
const fromEmail = process.env.EMAIL_FROM;
const isProduction = config.app.environment === 'production';

const canSendEmails = !!resend && !!fromEmail;

if (!canSendEmails) {
    logger.warn('[Email Service] RESEND_API_KEY or EMAIL_FROM not set. Email sending is disabled. Emails will be logged to the console.');
}

/**
 * A generic email sending wrapper that either uses Resend or logs to the console.
 * @param to Recipient's email address.
 * @param subject Email subject.
 * @param text The plain text body of the email.
 * @param context A description of the email being sent for logging.
 */
async function sendEmail(to: string, subject: string, text: string, context: string): Promise<void> {
    if (!canSendEmails) {
        logger.info(`[Email Simulation] TO: ${to} | SUBJECT: ${subject} | CONTEXT: ${context}`);
        logger.debug(`[Email Simulation] BODY:\n${text}`);
        return;
    }

    if (!resend || !fromEmail) {
        logger.error('[Email Service] Attempted to send email, but Resend or From Email is not configured.');
        return;
    }

    // In a non-production environment, always send to a test address if available
    const recipient = isProduction ? to : process.env.EMAIL_TEST_RECIPIENT || to;

    try {
        await resend.emails.send({
            from: fromEmail,
            to: recipient,
            subject: subject,
            text: text,
        });
        logger.info(`[Email Service] Successfully sent email. TO: ${recipient}, CONTEXT: ${context}`);
    } catch (error) {
        logger.error(`[Email Service] Failed to send email via Resend. TO: ${recipient}, CONTEXT: ${context}`, error);
        // In a production app, you might add this to a retry queue.
    }
}


/**
 * Sends an email alert.
 * @param alert The alert object containing details for the email.
 */
export async function sendEmailAlert(alert: Alert): Promise<void> {
  const metadata = alert.metadata as Record<string, unknown>;
  const subject = `AIventory Alert: ${alert.title} - ${metadata.productName || 'System Alert'}`;
  
  const body = `
    A new alert has been triggered in your AIventory account.

    Alert Type: ${alert.type.replace(/_/g, ' ')}
    Severity: ${alert.severity.toUpperCase()}
    Title: ${alert.title}
    Message: ${alert.message}

    Details:
    - Product: ${metadata.productName || 'N/A'}
    - SKU: ${metadata.sku || 'N/A'}
    - Current Stock: ${metadata.currentStock ?? 'N/A'}
    - Reorder Point: ${metadata.reorderPoint ?? 'N/A'}
    - Last Sold Date: ${metadata.lastSoldDate ? new Date(String(metadata.lastSoldDate)).toLocaleDateString() : 'N/A'}
    - Current Value: $${((metadata.value as number) / 100).toLocaleString()}

    You can view this alert in your AIventory dashboard.
  `.trim().replace(/^ */gm, '');

  // In a real app, this would fetch the user's actual email address.
  await sendEmail('user@example.com', subject, body, `Alert: ${alert.type}`);
}


/**
 * Sends a password reset email.
 * @param email The user's email address.
 * @param resetLink The password reset link.
 */
export async function sendPasswordResetEmail(email: string, resetLink: string): Promise<void> {
    const subject = "Reset Your AIventory Password";
    const body = `
        Hello,

        You requested a password reset for your AIventory account. Please click the link below to set a new password:
        ${resetLink}

        If you did not request this, you can safely ignore this email.

        Thanks,
        The AIventory Team
    `.trim();
    await sendEmail(email, subject, body, "Password Reset");
}

/**
 * Sends a welcome email to a new user.
 * @param email The new user's email address.
 */
export async function sendWelcomeEmail(email: string): Promise<void> {
    const subject = "Welcome to AIventory!";
    const body = `
        Hi there,

        Welcome to AIventory! We're excited to have you on board.
        Your account is all set up. You can log in and start exploring your AI-powered inventory dashboard now.

        If you have any questions, just reply to this email.

        Best,
        The AIventory Team
    `.trim();
    await sendEmail(email, subject, body, "Welcome Email");
}

type AnomalyWithExplanation = Anomaly & { explanation?: string };

/**
 * Sends a daily or weekly inventory digest email.
 * @param to The recipient's email address.
 * @param insights An object containing the data for the digest.
 */
export async function sendInventoryDigestEmail(to: string, insights: {
    summary: string;
    anomalies: AnomalyWithExplanation[];
    topDeadStock: { product_name: string; total_value: number; }[];
    topLowStock: Alert[];
}): Promise<void> {
    const subject = "Your Weekly Inventory Digest from AIventory";
    let body = `
Hello,

Here's your weekly summary of key inventory insights from AIventory.

---
AI Business Summary
---
${insights.summary}

`;

    if (insights.anomalies.length > 0) {
        body += `
---
Recent Anomalies Detected
---
`;
        insights.anomalies.forEach(anomaly => {
            body += `- ${anomaly.anomaly_type} on ${new Date(anomaly.date).toLocaleDateString()}: ${anomaly.explanation}\n`;
        });
    }

    if (insights.topLowStock.length > 0) {
        body += `
---
Top Items Low on Stock
---
`;
        insights.topLowStock.forEach(item => {
            const metadata = item.metadata as Record<string, unknown>;
            body += `- ${metadata.productName} (${metadata.currentStock} units left)\n`;
        });
    }
    
    if (insights.topDeadStock.length > 0) {
        body += `
---
Top Dead Stock Items
---
`;
        insights.topDeadStock.forEach(item => {
            body += `- ${item.product_name} ($${item.total_value.toLocaleString(undefined, { maximumFractionDigits: 0 })} in tied-up capital)\n`;
        });
    }

    body += `
    
View more details on your dashboard: ${config.app.url}/insights

Best,
The AIventory Team
    `.trim();
    
    await sendEmail(to, subject, body, 'Inventory Digest');
}
