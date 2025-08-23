'use server';

/**
 * Advanced Redis Caching Service
 * Part of Technical Infrastructure Improvements - Phase 2
 */

import { redisClient, isRedisEnabled } from '@/lib/redis';
import { logError } from '@/lib/error-handler';

// Cache strategy types
type CacheStrategy = 'write-through' | 'write-behind' | 'cache-aside' | 'refresh-ahead';

interface CacheConfig {
  ttl: number; // Time to live in seconds
  strategy: CacheStrategy;
  compression?: boolean;
  tags?: string[];
}

interface CacheMetrics {
  hits: number;
  misses: number;
  sets: number;
  deletes: number;
  errors: number;
  avgResponseTime: number;
}

// Default cache configurations for different data types
const CACHE_CONFIGS: Record<string, CacheConfig> = {
  inventory: { ttl: 300, strategy: 'write-through', tags: ['inventory'] }, // 5 minutes
  sales: { ttl: 600, strategy: 'cache-aside', tags: ['sales'] }, // 10 minutes
  analytics: { ttl: 1800, strategy: 'refresh-ahead', tags: ['analytics'] }, // 30 minutes
  user_session: { ttl: 3600, strategy: 'write-through', tags: ['auth'] }, // 1 hour
  dashboard: { ttl: 180, strategy: 'cache-aside', tags: ['dashboard'] }, // 3 minutes
  integration_health: { ttl: 120, strategy: 'write-through', tags: ['integrations'] }, // 2 minutes
  forecasting: { ttl: 3600, strategy: 'refresh-ahead', tags: ['forecasting'] }, // 1 hour
  conflict_resolution: { ttl: 900, strategy: 'write-through', tags: ['conflicts'] } // 15 minutes
};

class AdvancedCacheService {
  private static instance: AdvancedCacheService;
  private metrics: CacheMetrics = {
    hits: 0,
    misses: 0,
    sets: 0,
    deletes: 0,
    errors: 0,
    avgResponseTime: 0
  };
  private responseTimes: number[] = [];

  static getInstance(): AdvancedCacheService {
    if (!AdvancedCacheService.instance) {
      AdvancedCacheService.instance = new AdvancedCacheService();
    }
    return AdvancedCacheService.instance;
  }

  private updateResponseTime(time: number) {
    this.responseTimes.push(time);
    if (this.responseTimes.length > 100) {
      this.responseTimes = this.responseTimes.slice(-100);
    }
    this.metrics.avgResponseTime = this.responseTimes.reduce((a, b) => a + b, 0) / this.responseTimes.length;
  }

  // Get cache key with namespace
  private getCacheKey(key: string, namespace?: string): string {
    return namespace ? `${namespace}:${key}` : key;
  }

  // Compress data if enabled
  private compressData(data: any, _config: CacheConfig): string {
    const serialized = JSON.stringify(data);
    // For now, return as-is. In production, implement gzip compression
    return serialized;
  }

  // Decompress data if needed
  private decompressData(data: string, _config: CacheConfig): any {
    // For now, parse directly. In production, implement gzip decompression
    return JSON.parse(data);
  }

  // Set cache with advanced options
  async set(
    key: string, 
    value: any, 
    cacheType: string = 'default',
    namespace?: string
  ): Promise<boolean> {
    if (!isRedisEnabled) return false;

    const startTime = Date.now();
    const cacheKey = this.getCacheKey(key, namespace);
    const config = CACHE_CONFIGS[cacheType] || { ttl: 300, strategy: 'cache-aside' };

    try {
      const serializedValue = this.compressData(value, config);
      
      // Set with TTL
      const result = await redisClient.setex(cacheKey, config.ttl, serializedValue);
      
      // Add tags for cache invalidation
      if (config.tags) {
        for (const tag of config.tags) {
          await redisClient.sadd(`tag:${tag}`, cacheKey);
          await redisClient.expire(`tag:${tag}`, config.ttl);
        }
      }

      this.metrics.sets++;
      this.updateResponseTime(Date.now() - startTime);
      
      return result === 'OK';
    } catch (error) {
      this.metrics.errors++;
      logError(`Cache set failed for key: ${cacheKey}`, error as Error);
      return false;
    }
  }

  // Get cache with metrics
  async get<T>(
    key: string, 
    cacheType: string = 'default',
    namespace?: string
  ): Promise<T | null> {
    if (!isRedisEnabled) return null;

    const startTime = Date.now();
    const cacheKey = this.getCacheKey(key, namespace);
    const config = CACHE_CONFIGS[cacheType] || { ttl: 300, strategy: 'cache-aside' };

    try {
      const cachedValue = await redisClient.get(cacheKey);
      
      this.updateResponseTime(Date.now() - startTime);
      
      if (cachedValue) {
        this.metrics.hits++;
        return this.decompressData(cachedValue, config);
      } else {
        this.metrics.misses++;
        return null;
      }
    } catch (error) {
      this.metrics.errors++;
      logError(`Cache get failed for key: ${cacheKey}`, error as Error);
      return null;
    }
  }

  // Get or set pattern (cache-aside)
  async getOrSet<T>(
    key: string,
    fetcher: () => Promise<T>,
    cacheType: string = 'default',
    namespace?: string
  ): Promise<T> {
    // Try to get from cache first
    const cached = await this.get<T>(key, cacheType, namespace);
    if (cached !== null) {
      return cached;
    }

    // Fetch fresh data
    const freshData = await fetcher();
    
    // Set in cache
    await this.set(key, freshData, cacheType, namespace);
    
    return freshData;
  }

  // Delete cache entry
  async delete(key: string, namespace?: string): Promise<boolean> {
    if (!isRedisEnabled) return false;

    const cacheKey = this.getCacheKey(key, namespace);
    
    try {
      const result = await redisClient.del(cacheKey);
      this.metrics.deletes++;
      return result > 0;
    } catch (error) {
      this.metrics.errors++;
      logError(`Cache delete failed for key: ${cacheKey}`, error as Error);
      return false;
    }
  }

  // Invalidate cache by tags
  async invalidateByTags(tags: string[]): Promise<number> {
    if (!isRedisEnabled) return 0;

    let deletedCount = 0;
    
    try {
      for (const tag of tags) {
        const keys = await redisClient.smembers(`tag:${tag}`);
        if (keys.length > 0) {
          const deleted = await redisClient.del(...keys);
          deletedCount += deleted;
          
          // Clean up the tag set
          await redisClient.del(`tag:${tag}`);
        }
      }
      
      return deletedCount;
    } catch (error) {
      this.metrics.errors++;
      logError(`Cache invalidation failed for tags: ${tags.join(', ')}`, error as Error);
      return 0;
    }
  }

  // Multi-get for batch operations
  async mget<T>(keys: string[], cacheType: string = 'default', namespace?: string): Promise<(T | null)[]> {
    if (!isRedisEnabled) return keys.map(() => null);

    const cacheKeys = keys.map(key => this.getCacheKey(key, namespace));
    const config = CACHE_CONFIGS[cacheType] || { ttl: 300, strategy: 'cache-aside' };

    try {
      const values = await redisClient.mget(...cacheKeys);
      
      return values.map((value) => {
        if (value) {
          this.metrics.hits++;
          return this.decompressData(value, config);
        } else {
          this.metrics.misses++;
          return null;
        }
      });
    } catch (error) {
      this.metrics.errors++;
      logError(`Cache mget failed for keys: ${cacheKeys.join(', ')}`, error as Error);
      return keys.map(() => null);
    }
  }

  // Multi-set for batch operations
  async mset(keyValuePairs: Array<{key: string, value: any}>, cacheType: string = 'default', namespace?: string): Promise<boolean> {
    if (!isRedisEnabled) return false;

    const config = CACHE_CONFIGS[cacheType] || { ttl: 300, strategy: 'cache-aside' };

    try {
      // Use pipeline for better performance
      const pipeline = redisClient.pipeline();
      
      for (const {key, value} of keyValuePairs) {
        const cacheKey = this.getCacheKey(key, namespace);
        const serializedValue = this.compressData(value, config);
        pipeline.setex(cacheKey, config.ttl, serializedValue);
        
        // Add tags
        if (config.tags) {
          for (const tag of config.tags) {
            pipeline.sadd(`tag:${tag}`, cacheKey);
            pipeline.expire(`tag:${tag}`, config.ttl);
          }
        }
      }
      
      await pipeline.exec();
      this.metrics.sets += keyValuePairs.length;
      
      return true;
    } catch (error) {
      this.metrics.errors++;
      logError(`Cache mset failed`, error as Error);
      return false;
    }
  }

  // Increment counter with expiration
  async increment(key: string, increment: number = 1, ttl: number = 3600, namespace?: string): Promise<number> {
    if (!isRedisEnabled) return 0;

    const cacheKey = this.getCacheKey(key, namespace);
    
    try {
      const pipeline = redisClient.pipeline();
      pipeline.incrby(cacheKey, increment);
      pipeline.expire(cacheKey, ttl);
      
      const results = await pipeline.exec();
      return results?.[0]?.[1] as number || 0;
    } catch (error) {
      this.metrics.errors++;
      logError(`Cache increment failed for key: ${cacheKey}`, error as Error);
      return 0;
    }
  }

  // Get cache metrics
  getMetrics(): CacheMetrics {
    const hitRate = this.metrics.hits + this.metrics.misses > 0 
      ? (this.metrics.hits / (this.metrics.hits + this.metrics.misses)) * 100 
      : 0;
    
    return {
      ...this.metrics,
      hitRate
    } as CacheMetrics & {hitRate: number};
  }

  // Clear all cache metrics
  resetMetrics(): void {
    this.metrics = {
      hits: 0,
      misses: 0,
      sets: 0,
      deletes: 0,
      errors: 0,
      avgResponseTime: 0
    };
    this.responseTimes = [];
  }

  // Get cache info
  async getCacheInfo(): Promise<any> {
    if (!isRedisEnabled) return null;

    try {
      const info = await redisClient.info('memory');
      const keyspace = await redisClient.info('keyspace');
      
      return {
        memory: info,
        keyspace: keyspace,
        metrics: this.getMetrics()
      };
    } catch (error) {
      logError('Failed to get cache info', error as Error);
      return null;
    }
  }
}

// Singleton instance
const cacheService = AdvancedCacheService.getInstance();

// Export convenience functions
export async function setCache(key: string, value: any, cacheType?: string, namespace?: string): Promise<boolean> {
  return cacheService.set(key, value, cacheType, namespace);
}

export async function getCache<T>(key: string, cacheType?: string, namespace?: string): Promise<T | null> {
  return cacheService.get<T>(key, cacheType, namespace);
}

export async function getOrSetCache<T>(
  key: string, 
  fetcher: () => Promise<T>, 
  cacheType?: string, 
  namespace?: string
): Promise<T> {
  return cacheService.getOrSet(key, fetcher, cacheType, namespace);
}

export async function deleteCache(key: string, namespace?: string): Promise<boolean> {
  return cacheService.delete(key, namespace);
}

export async function invalidateCacheByTags(tags: string[]): Promise<number> {
  return cacheService.invalidateByTags(tags);
}

export async function incrementCounter(key: string, increment?: number, ttl?: number, namespace?: string): Promise<number> {
  return cacheService.increment(key, increment, ttl, namespace);
}

export async function getCacheMetrics(): Promise<CacheMetrics & {hitRate: number}> {
  return cacheService.getMetrics() as CacheMetrics & {hitRate: number};
}

export async function getCacheInfo(): Promise<any> {
  return cacheService.getCacheInfo();
}

export { AdvancedCacheService };
