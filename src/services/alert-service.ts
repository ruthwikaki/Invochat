
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logger } from '@/lib/logger';
import type { Alert } from '@/types';
import { CompanySettingsSchema, type CompanySettings } from '@/types';

// This file provides direct-to-database functions for handling alerts
// and their settings, aligning with the latest database schema.

export async function getAlertsWithStatus(companyId: string): Promise<Alert[]> {
  const supabase = getServiceRoleClient();
  const { data, error } = await supabase
    .rpc('get_alerts_with_status', { p_company_id: companyId });
  
  if (error) {
    logger.error('Failed to fetch alerts from get_alerts_with_status', { error: error.message, companyId });
    return [];
  }
  
  return (data || []) as Alert[];
}

export async function getAlertSettings(companyId: string): Promise<CompanySettings> {
  const supabase = getServiceRoleClient();
  const { data, error } = await supabase
    .from('company_settings')
    .select('*')
    .eq('company_id', companyId)
    .single();
  
  if (error) {
    logger.error('Failed to fetch alert settings', { error: error.message, companyId });
    // This will create settings if they don't exist, which is handled by the getSettings function
    const { data: newSettings, error: creationError } = await supabase.from('company_settings').insert({ company_id: companyId }).select().single();
    if(creationError) {
        throw new Error('Failed to create default settings');
    }
    return CompanySettingsSchema.parse(newSettings);
  }
  
  return CompanySettingsSchema.parse(data || {});
}

export async function updateAlertSettings(companyId: string, settings: Partial<CompanySettings>) {
  const supabase = getServiceRoleClient();
  const { error } = await supabase
    .from('company_settings')
    .update({ alert_settings: settings.alert_settings ? JSON.parse(JSON.stringify(settings.alert_settings)) : null }) 
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
    throw error;
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
    throw error;
  }
}
