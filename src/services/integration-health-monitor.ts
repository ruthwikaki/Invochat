'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { redisClient, isRedisEnabled } from '@/lib/redis';
import type { Integration } from '@/types';

export interface IntegrationHealthStatus {
  integrationId: string;
  companyId: string;
  platform: string;
  shopName: string;
  status: 'healthy' | 'warning' | 'critical' | 'offline';
  lastSyncAt: string | null;
  syncStatus: string | null;
  healthScore: number; // 0-100
  metrics: {
    syncSuccessRate: number;
    avgSyncDuration: number;
    errorRate: number;
    webhookDeliveryRate: number;
    dataConsistencyScore: number;
  };
  issues: HealthIssue[];
  recommendations: string[];
}

export interface HealthIssue {
  type: 'sync_failure' | 'webhook_miss' | 'data_inconsistency' | 'rate_limit' | 'auth_error' | 'timeout';
  severity: 'low' | 'medium' | 'high' | 'critical';
  message: string;
  timestamp: string;
  count: number;
}

export interface IntegrationMetrics {
  totalSyncs: number;
  successfulSyncs: number;
  failedSyncs: number;
  avgSyncDuration: number;
  lastSyncDuration: number;
  webhooksReceived: number;
  webhooksProcessed: number;
  dataInconsistencies: number;
  rateLimitHits: number;
  authErrors: number;
  timeouts: number;
}

class IntegrationHealthMonitor {
  private static instance: IntegrationHealthMonitor;
  
  private constructor() {}
  
  static getInstance(): IntegrationHealthMonitor {
    if (!IntegrationHealthMonitor.instance) {
      IntegrationHealthMonitor.instance = new IntegrationHealthMonitor();
    }
    return IntegrationHealthMonitor.instance;
  }

  async getIntegrationsHealth(companyId: string): Promise<IntegrationHealthStatus[]> {
    try {
      const supabase = getServiceRoleClient();
      
      // Get all integrations for the company
      const { data: integrations, error } = await supabase
        .from('integrations')
        .select('*')
        .eq('company_id', companyId)
        .eq('is_active', true);

      if (error) throw error;
      if (!integrations) return [];

      const healthStatuses = await Promise.all(
        integrations.map(integration => this.assessIntegrationHealth(integration as Integration))
      );

      return healthStatuses;
    } catch (error) {
      logError(error, { context: 'Failed to get integrations health', companyId });
      return [];
    }
  }

  async assessIntegrationHealth(integration: Integration): Promise<IntegrationHealthStatus> {
    const metrics = await this.getIntegrationMetrics(integration.id);
    const issues = await this.detectHealthIssues(integration, metrics);
    const healthScore = this.calculateHealthScore(metrics, issues);
    const status = this.determineHealthStatus(healthScore, issues);
    const recommendations = this.generateRecommendations(issues, metrics);

    return {
      integrationId: integration.id,
      companyId: integration.company_id,
      platform: integration.platform,
      shopName: integration.shop_name || 'Unknown Shop',
      status,
      lastSyncAt: integration.last_sync_at,
      syncStatus: integration.sync_status,
      healthScore,
      metrics: {
        syncSuccessRate: metrics.totalSyncs > 0 ? (metrics.successfulSyncs / metrics.totalSyncs) * 100 : 100,
        avgSyncDuration: metrics.avgSyncDuration,
        errorRate: metrics.totalSyncs > 0 ? (metrics.failedSyncs / metrics.totalSyncs) * 100 : 0,
        webhookDeliveryRate: metrics.webhooksReceived > 0 ? (metrics.webhooksProcessed / metrics.webhooksReceived) * 100 : 100,
        dataConsistencyScore: Math.max(0, 100 - (metrics.dataInconsistencies * 10)),
      },
      issues,
      recommendations,
    };
  }

  private async getIntegrationMetrics(integrationId: string): Promise<IntegrationMetrics> {
    const supabase = getServiceRoleClient();
    
    // Get sync history from the last 7 days
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    
    try {
      // Get sync metrics from audit logs or a dedicated sync_history table
      const [syncHistoryResult, webhookResult] = await Promise.all([
        supabase
          .from('audit_log')
          .select('action, details, created_at')
          .eq('action', 'integration_sync')
          .contains('details', { integration_id: integrationId })
          .gte('created_at', sevenDaysAgo)
          .order('created_at', { ascending: false }),
        
        supabase
          .from('webhook_events')
          .select('*')
          .eq('integration_id', integrationId)
          .gte('created_at', sevenDaysAgo)
      ]);

      const syncHistory = syncHistoryResult.data || [];
      const webhookEvents = webhookResult.data || [];

      // Calculate metrics
      const totalSyncs = syncHistory.length;
      const successfulSyncs = syncHistory.filter(log => 
        log.details && (log.details as any).status === 'success'
      ).length;
      const failedSyncs = totalSyncs - successfulSyncs;

      const syncDurations = syncHistory
        .map(log => (log.details as any)?.duration_ms)
        .filter(duration => typeof duration === 'number');
      
      const avgSyncDuration = syncDurations.length > 0 
        ? syncDurations.reduce((sum, duration) => sum + duration, 0) / syncDurations.length
        : 0;

      const lastSyncDuration = syncDurations[0] || 0;

      // Redis-based metrics (if available)
      let rateLimitHits = 0;
      let authErrors = 0;
      let timeouts = 0;

      if (isRedisEnabled) {
        const metricsKey = `integration_metrics:${integrationId}`;
        const redisMetrics = await redisClient.hgetall(metricsKey);
        rateLimitHits = parseInt(redisMetrics.rate_limit_hits || '0');
        authErrors = parseInt(redisMetrics.auth_errors || '0');
        timeouts = parseInt(redisMetrics.timeouts || '0');
      }

      return {
        totalSyncs,
        successfulSyncs,
        failedSyncs,
        avgSyncDuration,
        lastSyncDuration,
        webhooksReceived: webhookEvents.length,
        webhooksProcessed: webhookEvents.length, // Assume all received webhooks are processed
        dataInconsistencies: 0, // Would need specific data consistency checks
        rateLimitHits,
        authErrors,
        timeouts,
      };
    } catch (error) {
      logError(error, { context: 'Failed to get integration metrics', integrationId });
      return {
        totalSyncs: 0,
        successfulSyncs: 0,
        failedSyncs: 0,
        avgSyncDuration: 0,
        lastSyncDuration: 0,
        webhooksReceived: 0,
        webhooksProcessed: 0,
        dataInconsistencies: 0,
        rateLimitHits: 0,
        authErrors: 0,
        timeouts: 0,
      };
    }
  }

  private async detectHealthIssues(integration: Integration, metrics: IntegrationMetrics): Promise<HealthIssue[]> {
    const issues: HealthIssue[] = [];
    const now = new Date().toISOString();

    // Check for sync failures
    if (metrics.totalSyncs > 0 && metrics.failedSyncs / metrics.totalSyncs > 0.2) {
      issues.push({
        type: 'sync_failure',
        severity: metrics.failedSyncs / metrics.totalSyncs > 0.5 ? 'critical' : 'high',
        message: `High sync failure rate: ${Math.round((metrics.failedSyncs / metrics.totalSyncs) * 100)}%`,
        timestamp: now,
        count: metrics.failedSyncs,
      });
    }

    // Check for stale data (no sync in last 24 hours)
    if (integration.last_sync_at) {
      const lastSyncTime = new Date(integration.last_sync_at);
      const hoursSinceLastSync = (Date.now() - lastSyncTime.getTime()) / (1000 * 60 * 60);
      
      if (hoursSinceLastSync > 24) {
        issues.push({
          type: 'sync_failure',
          severity: hoursSinceLastSync > 72 ? 'critical' : 'medium',
          message: `No sync activity for ${Math.round(hoursSinceLastSync)} hours`,
          timestamp: now,
          count: 1,
        });
      }
    }

    // Check for authentication errors
    if (metrics.authErrors > 0) {
      issues.push({
        type: 'auth_error',
        severity: 'high',
        message: `Authentication errors detected: ${metrics.authErrors} occurrences`,
        timestamp: now,
        count: metrics.authErrors,
      });
    }

    // Check for rate limiting
    if (metrics.rateLimitHits > 10) {
      issues.push({
        type: 'rate_limit',
        severity: 'medium',
        message: `Frequent rate limiting: ${metrics.rateLimitHits} hits`,
        timestamp: now,
        count: metrics.rateLimitHits,
      });
    }

    // Check for timeouts
    if (metrics.timeouts > 5) {
      issues.push({
        type: 'timeout',
        severity: 'medium',
        message: `Connection timeouts: ${metrics.timeouts} occurrences`,
        timestamp: now,
        count: metrics.timeouts,
      });
    }

    // Check for slow syncs
    if (metrics.avgSyncDuration > 300000) { // 5 minutes
      issues.push({
        type: 'sync_failure',
        severity: 'low',
        message: `Slow sync performance: ${Math.round(metrics.avgSyncDuration / 1000)}s average`,
        timestamp: now,
        count: 1,
      });
    }

    // Check sync status
    if (integration.sync_status === 'failed') {
      issues.push({
        type: 'sync_failure',
        severity: 'high',
        message: 'Last sync failed',
        timestamp: now,
        count: 1,
      });
    }

    return issues;
  }

  private calculateHealthScore(metrics: IntegrationMetrics, issues: HealthIssue[]): number {
    let score = 100;

    // Deduct points for sync failures
    if (metrics.totalSyncs > 0) {
      const failureRate = metrics.failedSyncs / metrics.totalSyncs;
      score -= failureRate * 40; // Up to 40 points off for 100% failure rate
    }

    // Deduct points for issues based on severity
    issues.forEach(issue => {
      switch (issue.severity) {
        case 'critical':
          score -= 25;
          break;
        case 'high':
          score -= 15;
          break;
        case 'medium':
          score -= 10;
          break;
        case 'low':
          score -= 5;
          break;
      }
    });

    // Deduct points for performance issues
    if (metrics.avgSyncDuration > 60000) { // 1 minute
      score -= Math.min(20, (metrics.avgSyncDuration - 60000) / 10000);
    }

    return Math.max(0, Math.round(score));
  }

  private determineHealthStatus(healthScore: number, issues: HealthIssue[]): 'healthy' | 'warning' | 'critical' | 'offline' {
    const hasCriticalIssue = issues.some(issue => issue.severity === 'critical');
    
    if (hasCriticalIssue || healthScore < 25) {
      return 'critical';
    }
    
    if (healthScore < 60) {
      return 'warning';
    }
    
    if (healthScore < 90) {
      return 'warning';
    }
    
    return 'healthy';
  }

  private generateRecommendations(issues: HealthIssue[], metrics: IntegrationMetrics): string[] {
    const recommendations: string[] = [];

    issues.forEach(issue => {
      switch (issue.type) {
        case 'sync_failure':
          if (issue.message.includes('No sync activity')) {
            recommendations.push('Schedule more frequent syncs or check webhook configuration');
          } else if (issue.message.includes('High sync failure rate')) {
            recommendations.push('Review integration credentials and API endpoint status');
          } else if (issue.message.includes('Slow sync performance')) {
            recommendations.push('Consider implementing incremental sync or optimizing data queries');
          }
          break;
        
        case 'auth_error':
          recommendations.push('Update integration credentials and verify API permissions');
          break;
        
        case 'rate_limit':
          recommendations.push('Implement exponential backoff and reduce sync frequency');
          break;
        
        case 'timeout':
          recommendations.push('Check network connectivity and increase timeout values');
          break;
        
        case 'webhook_miss':
          recommendations.push('Verify webhook endpoints and implement webhook retry mechanism');
          break;
        
        case 'data_inconsistency':
          recommendations.push('Run data reconciliation and implement data validation checks');
          break;
      }
    });

    // Add general recommendations based on metrics
    if (metrics.totalSyncs === 0) {
      recommendations.push('Trigger initial sync to establish baseline data');
    }

    if (metrics.avgSyncDuration > 120000) { // 2 minutes
      recommendations.push('Optimize sync process by implementing batch processing');
    }

    // Remove duplicates
    return [...new Set(recommendations)];
  }

  async recordSyncMetric(integrationId: string, metricType: 'sync_start' | 'sync_success' | 'sync_failure' | 'rate_limit' | 'auth_error' | 'timeout', details?: any): Promise<void> {
    if (!isRedisEnabled) return;

    try {
      const metricsKey = `integration_metrics:${integrationId}`;
      const pipeline = redisClient.pipeline();

      switch (metricType) {
        case 'sync_start':
          pipeline.hset(metricsKey, 'last_sync_start', Date.now());
          break;
        
        case 'sync_success':
          pipeline.hincrby(metricsKey, 'successful_syncs', 1);
          pipeline.hset(metricsKey, 'last_successful_sync', Date.now());
          if (details?.duration) {
            pipeline.hset(metricsKey, 'last_sync_duration', details.duration);
          }
          break;
        
        case 'sync_failure':
          pipeline.hincrby(metricsKey, 'failed_syncs', 1);
          pipeline.hset(metricsKey, 'last_failed_sync', Date.now());
          break;
        
        case 'rate_limit':
          pipeline.hincrby(metricsKey, 'rate_limit_hits', 1);
          break;
        
        case 'auth_error':
          pipeline.hincrby(metricsKey, 'auth_errors', 1);
          break;
        
        case 'timeout':
          pipeline.hincrby(metricsKey, 'timeouts', 1);
          break;
      }

      pipeline.expire(metricsKey, 604800); // Keep metrics for 7 days
      await pipeline.exec();
    } catch (error) {
      logError(error, { context: 'Failed to record sync metric', integrationId, metricType });
    }
  }

  async generateHealthReport(companyId: string): Promise<{
    summary: {
      totalIntegrations: number;
      healthyIntegrations: number;
      warningIntegrations: number;
      criticalIntegrations: number;
      avgHealthScore: number;
    };
    integrations: IntegrationHealthStatus[];
    recommendations: string[];
  }> {
    const integrations = await this.getIntegrationsHealth(companyId);
    
    const summary = {
      totalIntegrations: integrations.length,
      healthyIntegrations: integrations.filter(i => i.status === 'healthy').length,
      warningIntegrations: integrations.filter(i => i.status === 'warning').length,
      criticalIntegrations: integrations.filter(i => i.status === 'critical').length,
      avgHealthScore: integrations.length > 0 
        ? Math.round(integrations.reduce((sum, i) => sum + i.healthScore, 0) / integrations.length)
        : 100,
    };

    // Collect all recommendations and prioritize them
    const allRecommendations = integrations.flatMap(i => i.recommendations);
    const uniqueRecommendations = [...new Set(allRecommendations)];

    return {
      summary,
      integrations,
      recommendations: uniqueRecommendations,
    };
  }
}

export const integrationHealthMonitor = IntegrationHealthMonitor.getInstance();
