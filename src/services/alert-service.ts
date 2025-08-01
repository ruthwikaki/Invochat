

'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logger } from '@/lib/logger';
import type { Alert } from '@/types';
import { z } from 'zod';

// Define the shape of alert settings for validation
export const AlertSettingsSchema = z.object({
  email_notifications: z.boolean().default(true),
  morning_briefing_enabled: z.boolean().default(true),
  morning_briefing_time: z.string().regex(/^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$/).default('09:00'), // HH:MM format
  low_stock_threshold: z.number().int().positive().default(10),
  critical_stock_threshold: z.number().int().positive().default(5),
});
export type AlertSettings = z.infer<typeof AlertSettingsSchema>;


export async function getAlertsWithStatus(companyId: string): Promise<Alert[]> {
  const supabase = getServiceRoleClient();
  const { data, error } = await supabase
    .rpc('get_alerts_with_status', { p_company_id: companyId });
  
  if (error) {
    logger.error('Failed to fetch alerts from get_alerts_with_status', { error: error.message, companyId });
    return [];
  }
  
  // The data from the RPC call is expected to be JSON, which needs parsing.
  return (data || []).map((a: any) => a as Alert);
}

export async function getAlertSettings(companyId: string): Promise<AlertSettings> {
  const supabase = getServiceRoleClient();
  const { data, error } = await supabase
    .from('company_settings')
    .select('alert_settings')
    .eq('company_id', companyId)
    .single();
  
  if (error) {
    logger.error('Failed to fetch alert settings', { error: error.message, companyId });
    return AlertSettingsSchema.parse({}); // Return default settings on error
  }
  
  return AlertSettingsSchema.parse(data?.alert_settings || {});
}

export async function updateAlertSettings(companyId: string, settings: Partial<AlertSettings>) {
  const supabase = getServiceRoleClient();
  const { error } = await supabase
    .from('company_settings')
    .update({ alert_settings: settings })
    .eq('company_id', companyId);
  
  if (error) {
    logger.error('Failed to update alert settings', { error: error.message, companyId });
    throw error;
  }
}

 export async function markAlertAsRead(alertId: string, companyId: string) {
  const supabase = getServiceRoleClient();
  const { error } = await supabase
    .from('alert_history')
    .upsert(
      { 
        company_id: companyId,
        alert_id: alertId, 
        status: 'read', 
        read_at: new Date().toISOString()
      },
      { onConflict: 'company_id, alert_id' }
    );
  
  if (error) {
    logger.error('Failed to mark alert as read', { error: error.message, alertId });
  }
}

export async function dismissAlert(alertId: string, companyId: string) {
  const supabase = getServiceRoleClient();
  const { error } = await supabase
    .from('alert_history')
    .upsert(
      {
        company_id: companyId,
        alert_id: alertId,
        status: 'dismissed',
        dismissed_at: new Date().toISOString()
      },
      { onConflict: 'company_id, alert_id' }
     );

  if (error) {
    logger.error('Failed to dismiss alert', { error: error.message, alertId });
  }
}
