
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { sendInventoryDigestEmail } from '@/services/email';
import { logger } from '@/lib/logger';
import { generateMorningBriefing } from '@/ai/flows/morning-briefing-flow';
import { getDashboardMetrics } from '@/services/database';
import type { Alert, DashboardMetrics } from '@/types';
import { getAlertsWithStatus, getAlertSettings } from './alert-service';


export async function processDailyAlerts() {
    logger.info('Starting daily alert processing job...');
    const supabase = getServiceRoleClient();
    
    try {
        const { data: companies, error } = await supabase
            .from('companies')
            .select('id, name');
        
        if (error) throw error;
        
        for (const company of companies || []) {
            await processCompanyAlerts(company.id, company.name);
        }
        
        logger.info('Daily alert processing job completed successfully.');
    } catch (error) {
        logger.error('Daily alert processing job failed', { error });
    }
}

async function processCompanyAlerts(companyId: string, companyName: string) {
    logger.info(`Processing alerts for company: ${companyName} (${companyId})`);
    const supabase = getServiceRoleClient();
    try {
      const settings = await getAlertSettings(companyId);
      
      if (!settings?.morning_briefing_enabled || !settings?.email_notifications) {
        logger.info(`Skipping email briefing for company ${companyName} as it is disabled.`);
        return;
      }

      const { data: users, error } = await supabase
        .from('company_users')
        .select('users(email)')
        .eq('company_id', companyId)
        .in('role', ['Owner', 'Admin']);
      
      if (error) throw error;
      if (!users || users.length === 0) return;

      const userEmails = users.map(u => (u.users as any)?.email).filter(Boolean);

      // Generate alerts and briefing
      const alerts = await getAlertsWithStatus(companyId);
      const metrics = await getDashboardMetrics(companyId, '30d');
      const briefing = await generateMorningBriefing({ 
        metrics, 
        companyName 
      });

      // Send emails to all admins/owners of the company
      for (const email of userEmails) {
        await sendDailyDigest(email, briefing, alerts, metrics);
      }
      
    } catch (error) {
      logger.error(`Failed to process alerts for company ${companyId}`, { error });
    }
}

async function sendDailyDigest(
    email: string,
    briefing: Awaited<ReturnType<typeof generateMorningBriefing>>,
    alerts: Alert[],
    metrics: DashboardMetrics
) {
    const lowStockAlerts = alerts.filter(a => a.type === 'low_stock');
    const deadStockItems = (metrics.top_products || [])
        .filter((p: any) => p.total_revenue === 0)
        .slice(0, 5)
        .map((p: any) => ({ product_name: p.product_name, total_value: 0 }));

    await sendInventoryDigestEmail(email, {
      summary: briefing.summary,
      anomalies: [], // Could be enhanced with a dedicated anomaly detection flow
      topDeadStock: deadStockItems,
      topLowStock: lowStockAlerts.slice(0, 5)
    });
}
