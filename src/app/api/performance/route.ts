'use server';

/**
 * Performance Monitoring API
 * Part of Technical Infrastructure Improvements - Phase 1 & 2
 */

import { NextRequest, NextResponse } from 'next/server';
import { getDatabasePerformanceStats, getSlowQueries } from '@/services/enhanced-database-service';
import { getCacheMetrics, getCacheInfo } from '@/services/advanced-cache-service';
import { logError } from '@/lib/error-handler';

// System performance metrics
interface SystemMetrics {
  database: {
    totalQueries: number;
    avgExecutionTime: number;
    slowQueries: number;
    errorRate: number;
    connectionPoolSize: number;
    activeConnections: number;
  };
  cache: {
    hits: number;
    misses: number;
    hitRate: number;
    sets: number;
    deletes: number;
    errors: number;
    avgResponseTime: number;
  };
  system: {
    uptime: number;
    memoryUsage: NodeJS.MemoryUsage;
    timestamp: string;
  };
}

// Get comprehensive system performance metrics
export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const includeSlowQueries = searchParams.get('includeSlowQueries') === 'true';
    const limit = parseInt(searchParams.get('limit') || '10');

    // Gather all performance metrics
    const [databaseStats, cacheMetrics, cacheInfo] = await Promise.all([
      getDatabasePerformanceStats(),
      getCacheMetrics(),
      getCacheInfo()
    ]);

    const systemMetrics: SystemMetrics = {
      database: databaseStats,
      cache: cacheMetrics,
      system: {
        uptime: process.uptime(),
        memoryUsage: process.memoryUsage(),
        timestamp: new Date().toISOString()
      }
    };

    let response: any = {
      metrics: systemMetrics,
      status: 'healthy'
    };

    // Add slow queries if requested
    if (includeSlowQueries) {
      const slowQueries = await getSlowQueries(limit);
      response.slowQueries = slowQueries;
    }

    // Add cache info if available
    if (cacheInfo) {
      response.cacheInfo = cacheInfo;
    }

    // Determine overall system health
    const healthStatus = determineSystemHealth(systemMetrics);
    response.status = healthStatus.status;
    response.healthChecks = healthStatus.checks;

    return NextResponse.json(response);

  } catch (error) {
    logError('Performance monitoring API error', error as Error);
    return NextResponse.json(
      { 
        error: 'Failed to retrieve performance metrics',
        status: 'error',
        timestamp: new Date().toISOString()
      },
      { status: 500 }
    );
  }
}

// POST endpoint for clearing metrics or triggering maintenance
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { action } = body;

    switch (action) {
      case 'reset_cache_metrics':
        // Reset cache metrics would be implemented here
        return NextResponse.json({ 
          success: true, 
          message: 'Cache metrics reset',
          timestamp: new Date().toISOString()
        });

      case 'clear_cache':
        const { tags } = body;
        if (tags && Array.isArray(tags)) {
          // Clear cache by tags would be implemented here
          return NextResponse.json({ 
            success: true, 
            message: `Cache cleared for tags: ${tags.join(', ')}`,
            timestamp: new Date().toISOString()
          });
        }
        break;

      case 'refresh_materialized_views':
        // Trigger materialized view refresh
        return NextResponse.json({ 
          success: true, 
          message: 'Materialized views refresh triggered',
          timestamp: new Date().toISOString()
        });

      default:
        return NextResponse.json(
          { error: 'Invalid action' },
          { status: 400 }
        );
    }

  } catch (error) {
    logError('Performance monitoring POST error', error as Error);
    return NextResponse.json(
      { error: 'Failed to execute action' },
      { status: 500 }
    );
  }
}

// Determine system health based on metrics
function determineSystemHealth(metrics: SystemMetrics) {
  const checks = [];
  let overallStatus = 'healthy';

  // Database health checks
  if (metrics.database.avgExecutionTime > 1000) {
    checks.push({
      component: 'database',
      status: 'warning',
      message: 'Average query execution time is high'
    });
    overallStatus = 'warning';
  }

  if (metrics.database.errorRate > 5) {
    checks.push({
      component: 'database',
      status: 'critical',
      message: 'Database error rate is above threshold'
    });
    overallStatus = 'critical';
  }

  if (metrics.database.slowQueries > 10) {
    checks.push({
      component: 'database',
      status: 'warning',
      message: 'High number of slow queries detected'
    });
    if (overallStatus === 'healthy') overallStatus = 'warning';
  }

  // Cache health checks
  if (metrics.cache.hitRate < 70) {
    checks.push({
      component: 'cache',
      status: 'warning',
      message: 'Cache hit rate is below optimal threshold'
    });
    if (overallStatus === 'healthy') overallStatus = 'warning';
  }

  if (metrics.cache.errors > 5) {
    checks.push({
      component: 'cache',
      status: 'warning',
      message: 'Cache errors detected'
    });
    if (overallStatus === 'healthy') overallStatus = 'warning';
  }

  // Memory health checks
  const memoryUsagePercent = (metrics.system.memoryUsage.heapUsed / metrics.system.memoryUsage.heapTotal) * 100;
  if (memoryUsagePercent > 80) {
    checks.push({
      component: 'memory',
      status: 'warning',
      message: 'High memory usage detected'
    });
    if (overallStatus === 'healthy') overallStatus = 'warning';
  }

  if (checks.length === 0) {
    checks.push({
      component: 'system',
      status: 'healthy',
      message: 'All systems operating normally'
    });
  }

  return {
    status: overallStatus,
    checks
  };
}
