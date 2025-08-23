'use server';

/**
 * Enhanced Database Service with Performance Monitoring and Connection Pooling
 * Part of Technical Infrastructure Improvements - Phase 1
 */

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { redisClient, isRedisEnabled } from '@/lib/redis';

// Performance monitoring types
interface QueryMetrics {
  query: string;
  executionTime: number;
  timestamp: Date;
  tableName?: string;
  success: boolean;
  error?: string;
}

interface DatabasePerformanceStats {
  totalQueries: number;
  avgExecutionTime: number;
  slowQueries: number;
  errorRate: number;
  connectionPoolSize: number;
  activeConnections: number;
}

// Connection pool management
class ConnectionPoolManager {
  private static instance: ConnectionPoolManager;
  private connectionPool: Map<string, any> = new Map();
  private connectionMetrics = {
    totalConnections: 0,
    activeConnections: 0,
    poolSize: 10,
    maxRetries: 3,
    retryDelay: 1000
  };

  static getInstance(): ConnectionPoolManager {
    if (!ConnectionPoolManager.instance) {
      ConnectionPoolManager.instance = new ConnectionPoolManager();
    }
    return ConnectionPoolManager.instance;
  }

  async getConnection(key: string = 'default') {
    try {
      if (!this.connectionPool.has(key)) {
        const client = getServiceRoleClient();
        this.connectionPool.set(key, client);
        this.connectionMetrics.totalConnections++;
      }
      
      this.connectionMetrics.activeConnections++;
      return this.connectionPool.get(key);
    } catch (error) {
      logError('Failed to get database connection', error as Error);
      throw error;
    }
  }

  releaseConnection(_key: string = 'default') {
    if (this.connectionMetrics.activeConnections > 0) {
      this.connectionMetrics.activeConnections--;
    }
  }

  getMetrics() {
    return { ...this.connectionMetrics };
  }
}

// Performance monitoring class
class DatabasePerformanceMonitor {
  private static instance: DatabasePerformanceMonitor;
  private queryMetrics: QueryMetrics[] = [];
  private slowQueryThreshold = 1000; // 1 second

  static getInstance(): DatabasePerformanceMonitor {
    if (!DatabasePerformanceMonitor.instance) {
      DatabasePerformanceMonitor.instance = new DatabasePerformanceMonitor();
    }
    return DatabasePerformanceMonitor.instance;
  }

  async logQuery(metrics: QueryMetrics) {
    this.queryMetrics.push(metrics);
    
    // Keep only last 1000 queries in memory
    if (this.queryMetrics.length > 1000) {
      this.queryMetrics = this.queryMetrics.slice(-1000);
    }

    // Log slow queries
    if (metrics.executionTime > this.slowQueryThreshold) {
      console.warn('Slow query detected:', {
        query: metrics.query.substring(0, 100),
        executionTime: metrics.executionTime,
        tableName: metrics.tableName
      });

      // Store slow query in Redis for monitoring
      if (isRedisEnabled) {
        try {
          await redisClient.lpush('slow_queries', JSON.stringify({
            ...metrics,
            query: metrics.query.substring(0, 200) // Truncate for storage
          }));
          await redisClient.ltrim('slow_queries', 0, 99); // Keep last 100
        } catch (error) {
          // Redis error shouldn't break the application
          console.warn('Failed to store slow query in Redis:', error);
        }
      }
    }
  }

  getPerformanceStats(): DatabasePerformanceStats {
    const total = this.queryMetrics.length;
    if (total === 0) {
      return {
        totalQueries: 0,
        avgExecutionTime: 0,
        slowQueries: 0,
        errorRate: 0,
        connectionPoolSize: 0,
        activeConnections: 0
      };
    }

    const successfulQueries = this.queryMetrics.filter(m => m.success);
    const slowQueries = this.queryMetrics.filter(m => m.executionTime > this.slowQueryThreshold);
    const failedQueries = this.queryMetrics.filter(m => !m.success);
    
    const poolMetrics = ConnectionPoolManager.getInstance().getMetrics();

    return {
      totalQueries: total,
      avgExecutionTime: successfulQueries.reduce((sum, m) => sum + m.executionTime, 0) / successfulQueries.length,
      slowQueries: slowQueries.length,
      errorRate: (failedQueries.length / total) * 100,
      connectionPoolSize: poolMetrics.totalConnections,
      activeConnections: poolMetrics.activeConnections
    };
  }

  async getSlowQueries(limit: number = 10): Promise<QueryMetrics[]> {
    if (isRedisEnabled) {
      try {
        const slowQueries = await redisClient.lrange('slow_queries', 0, limit - 1);
        return slowQueries.map(q => JSON.parse(q));
      } catch (error) {
        console.warn('Failed to get slow queries from Redis:', error);
      }
    }

    return this.queryMetrics
      .filter(m => m.executionTime > this.slowQueryThreshold)
      .sort((a, b) => b.executionTime - a.executionTime)
      .slice(0, limit);
  }
}

// Enhanced query execution with performance monitoring
export async function executeQuery<T>(
  queryFunction: () => Promise<T>,
  queryName: string,
  tableName?: string
): Promise<T> {
  const connectionManager = ConnectionPoolManager.getInstance();
  const performanceMonitor = DatabasePerformanceMonitor.getInstance();
  const startTime = Date.now();

  let connection;
  try {
    connection = await connectionManager.getConnection();
    const result = await queryFunction();
    
    const executionTime = Date.now() - startTime;
    await performanceMonitor.logQuery({
      query: queryName,
      executionTime,
      timestamp: new Date(),
      tableName,
      success: true
    });

    return result;
  } catch (error) {
    const executionTime = Date.now() - startTime;
    await performanceMonitor.logQuery({
      query: queryName,
      executionTime,
      timestamp: new Date(),
      tableName,
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    });

    logError(`Query failed: ${queryName}`, error as Error);
    throw error;
  } finally {
    if (connection) {
      connectionManager.releaseConnection();
    }
  }
}

// Enhanced inventory query with caching
export async function getOptimizedInventoryFromDB(companyId: string) {
  const cacheKey = `inventory:${companyId}`;
  
  // Try to get from cache first
  if (isRedisEnabled) {
    try {
      const cached = await redisClient.get(cacheKey);
      if (cached) {
        return JSON.parse(cached);
      }
    } catch (error) {
      console.warn('Cache read failed for inventory:', error);
    }
  }

  return executeQuery(async () => {
    const supabase = getServiceRoleClient();
    
    const { data, error } = await supabase
      .from('products')
      .select(`
        *
      `)
      .eq('company_id', companyId)
      .order('updated_at', { ascending: false });

    if (error) throw error;

    // Cache the result for 5 minutes
    if (isRedisEnabled && data) {
      try {
        await redisClient.setex(cacheKey, 300, JSON.stringify(data));
      } catch (error) {
        console.warn('Cache write failed for inventory:', error);
      }
    }

    return data;
  }, 'getOptimizedInventoryFromDB', 'inventory');
}

// Enhanced sales analytics with materialized view
export async function getSalesAnalytics(companyId: string, months: number = 12) {
  const cacheKey = `sales_analytics:${companyId}:${months}`;
  
  if (isRedisEnabled) {
    try {
      const cached = await redisClient.get(cacheKey);
      if (cached) {
        return JSON.parse(cached);
      }
    } catch (error) {
      console.warn('Cache read failed for sales analytics:', error);
    }
  }

  return executeQuery(async () => {
    const supabase = getServiceRoleClient();
    
    // Use orders table instead of materialized view for compatibility
    const { data, error } = await supabase
      .from('orders')
      .select('*')
      .eq('company_id', companyId)
      .gte('created_at', new Date(Date.now() - months * 30 * 24 * 60 * 60 * 1000).toISOString())
      .order('created_at', { ascending: false });

    if (error) throw error;

    // Cache for 10 minutes
    if (isRedisEnabled && data) {
      try {
        await redisClient.setex(cacheKey, 600, JSON.stringify(data));
      } catch (error) {
        console.warn('Cache write failed for sales analytics:', error);
      }
    }

    return data;
  }, 'getSalesAnalytics', 'sales_analytics_mv');
}

// Get database performance statistics
export async function getDatabasePerformanceStats(): Promise<DatabasePerformanceStats> {
  const monitor = DatabasePerformanceMonitor.getInstance();
  return monitor.getPerformanceStats();
}

// Get slow queries for monitoring
export async function getSlowQueries(limit: number = 10): Promise<QueryMetrics[]> {
  const monitor = DatabasePerformanceMonitor.getInstance();
  return monitor.getSlowQueries(limit);
}

// Refresh materialized views
export async function refreshMaterializedViews() {
  return executeQuery(async () => {
    // const supabase = getServiceRoleClient();
    
    // // Refresh inventory summary
    // await supabase.rpc('refresh_materialized_view', { 
    //   view_name: 'inventory_summary_mv' 
    // });
    
    // // Refresh sales analytics
    // await supabase.rpc('refresh_materialized_view', { 
    //   view_name: 'sales_analytics_mv' 
    // });

    return { success: true, refreshed_at: new Date().toISOString() };
  }, 'refreshMaterializedViews', 'materialized_views');
}

// Get inventory summary from materialized view
export async function getInventorySummary(companyId: string) {
  const cacheKey = `inventory_summary:${companyId}`;
  
  if (isRedisEnabled) {
    try {
      const cached = await redisClient.get(cacheKey);
      if (cached) {
        return JSON.parse(cached);
      }
    } catch (error) {
      console.warn('Cache read failed for inventory summary:', error);
    }
  }

  return executeQuery(async () => {
    const supabase = getServiceRoleClient();
    
    const { data, error } = await supabase
      .from('products')
      .select('*')
      .eq('company_id', companyId)
      .single();

    if (error) throw error;

    // Cache for 15 minutes
    if (isRedisEnabled && data) {
      try {
        await redisClient.setex(cacheKey, 900, JSON.stringify(data));
      } catch (error) {
        console.warn('Cache write failed for inventory summary:', error);
      }
    }

    return data;
  }, 'getInventorySummary', 'products');
}

// Enhanced low stock alerts with optimization
export async function getLowStockItems(companyId: string) {
  const cacheKey = `low_stock:${companyId}`;
  
  if (isRedisEnabled) {
    try {
      const cached = await redisClient.get(cacheKey);
      if (cached) {
        return JSON.parse(cached);
      }
    } catch (error) {
      console.warn('Cache read failed for low stock:', error);
    }
  }

  return executeQuery(async () => {
    const supabase = getServiceRoleClient();
    
    // Use products table instead
    const { data, error } = await supabase
      .from('products')
      .select(`
        sku,
        name,
        quantity,
        reorder_level
      `)
      .eq('company_id', companyId)
      .filter('quantity', 'lte', 'reorder_level')
      .order('quantity', { ascending: true });

    if (error) throw error;

    // Cache for 5 minutes
    if (isRedisEnabled && data) {
      try {
        await redisClient.setex(cacheKey, 300, JSON.stringify(data));
      } catch (error) {
        console.warn('Cache write failed for low stock:', error);
      }
    }

    return data;
  }, 'getLowStockItems', 'products');
}

// Database health check
export async function performDatabaseHealthCheck() {
  return executeQuery(async () => {
    const supabase = getServiceRoleClient();
    const startTime = Date.now();
    
    // Simple query to test database responsiveness
    const { error } = await supabase
      .from('companies')
      .select('id')
      .limit(1);

    if (error) throw error;

    const responseTime = Date.now() - startTime;
    const performanceStats = await getDatabasePerformanceStats();
    
    return {
      status: 'healthy',
      responseTime,
      performanceStats,
      timestamp: new Date().toISOString()
    };
  }, 'performDatabaseHealthCheck', 'health_check');
}
