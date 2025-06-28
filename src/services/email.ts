
'use server';

/**
 * @fileoverview
 * This file contains a simulated email service for sending alerts.
 * In a production environment, this would be replaced with a real email
 * sending service like Resend, SendGrid, or Nodemailer.
 */

import type { Alert } from '@/types';

/**
 * Simulates sending an email alert.
 * It constructs the email content and logs it to the console.
 * @param alert The alert object containing details for the email.
 */
export async function sendEmailAlert(alert: Alert): Promise<void> {
  console.log('--- SIMULATING EMAIL ALERT ---');
  
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

    This is a simulated email. To enable real email sending, integrate a service like
    Resend (https://resend.com) or Postmark (https://postmarkapp.com) here.
  `;

  console.log(`To: user@example.com`);
  console.log(`Subject: ${subject}`);
  console.log('Body:');
  console.log(body.trim());
  console.log('------------------------------');

  // In a real implementation, this would involve an API call to your email provider.
  // Example with Resend:
  //
  // import { Resend } from 'resend';
  // const resend = new Resend(process.env.RESEND_API_KEY);
  //
  // try {
  //   await resend.emails.send({
  //     from: 'invochat@yourdomain.com',
  //     to: 'recipient@example.com',
  //     subject: subject,
  //     text: body, // Or use a pre-made React component for HTML emails
  //   });
  //   console.log('Email sent successfully via Resend.');
  // } catch (error) {
  //   console.error('Failed to send email:', error);
  // }
}
