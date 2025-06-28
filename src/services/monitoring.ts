
'use server';

import { redisClient, isRedisEnabled } from '@/lib/redis';
import { logger } from '@/lib/logger';

if (isRedisEnabled) {
    logger.info('[Monitoring] Performance monitoring service is active.');
}

/**
 * Tracks the execution time of a specific AI query.
 * @param query The user's query string.
 * @param durationMs The execution time in milliseconds.
 */
export async function trackAiQueryPerformance(query: string, durationMs: number): Promise<void> {
    if (!isRedisEnabled) return;

    try {
        const pipeline = redisClient.pipeline();
        // Use a unique identifier for the query instance to avoid collisions in the log
        const queryIdentifier = `${new Date().toISOString()}|${query}`;

        // Add to a sorted set of slow queries, scored by duration
        pipeline.zadd('perf:ai_slow_log', durationMs, queryIdentifier);
        // Keep the log trimmed to the 100 slowest queries
        pipeline.zremrangebyrank('perf:ai_slow_log', 0, -101);

        // Increment total time and count to calculate average
        pipeline.incrbyfloat('perf:ai_total_duration', durationMs);
        pipeline.incr('perf:ai_total_count');

        await pipeline.exec();
    } catch (e) {
        logger.error('[Monitoring] Failed to track AI query performance:', e);
    }
}

/**
 * Tracks the execution time of a specific database function.
 * @param functionName The name of the database function being tracked.
 * @param durationMs The execution time in milliseconds.
 */
export async function trackDbQueryPerformance(functionName: string, durationMs: number): Promise<void> {
    if (!isRedisEnabled) return;
    try {
        const pipeline = redisClient.pipeline();
        const queryIdentifier = `${new Date().toISOString()}|${functionName}`;

        pipeline.zadd('perf:db_slow_log', durationMs, queryIdentifier);
        pipeline.zremrangebyrank('perf:db_slow_log', 0, -101);

        pipeline.incrbyfloat(`perf:db:${functionName}:total_duration`, durationMs);
        pipeline.incr(`perf:db:${functionName}:total_count`);

        await pipeline.exec();
    } catch (e) {
        logger.error(`[Monitoring] Failed to track DB query performance for ${functionName}:`, e);
    }
}

/**
 * Tracks the execution time of a server action or API endpoint.
 * @param endpointName The name of the endpoint being tracked.
 * @param durationMs The execution time in milliseconds.
 */
export async function trackEndpointPerformance(endpointName: string, durationMs: number): Promise<void> {
    if (!isRedisEnabled) return;

    try {
        const pipeline = redisClient.pipeline();
        const endpointIdentifier = `${new Date().toISOString()}|${endpointName}`;

        pipeline.zadd('perf:endpoint_slow_log', durationMs, endpointIdentifier);
        pipeline.zremrangebyrank('perf:endpoint_slow_log', 0, -101);

        pipeline.incrbyfloat(`perf:endpoint:${endpointName}:total_duration`, durationMs);
        pipeline.incr(`perf:endpoint:${endpointName}:total_count`);

        await pipeline.exec();
    } catch (e) {
        logger.error(`[Monitoring] Failed to track endpoint performance for ${endpointName}:`, e);
    }
}


/**
 * Increments the cache hit counter for a given cache type.
 * @param cacheType A descriptor for the cache (e.g., 'dashboard', 'ai_query').
 */
export async function incrementCacheHit(cacheType: string): Promise<void> {
    if (!isRedisEnabled) return;
    try {
        await redisClient.incr(`perf:cache_hits:${cacheType}`);
    } catch (e) {
        logger.error(`[Monitoring] Failed to increment cache hit for ${cacheType}:`, e);
    }
}

/**
 * Increments the cache miss counter for a given cache type.
 * @param cacheType A descriptor for the cache (e.g., 'dashboard', 'ai_query').
 */
export async function incrementCacheMiss(cacheType: string): Promise<void> {
    if (!isRedisEnabled) return;
    try {
        await redisClient.incr(`perf:cache_misses:${cacheType}`);
    } catch (e) {
        logger.error(`[Monitoring] Failed to increment cache miss for ${cacheType}:`, e);
    }
}
