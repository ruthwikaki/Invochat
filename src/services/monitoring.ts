
'use server';

// This monitoring service is a stub for a more robust implementation.
// In a production environment, this would be replaced with a proper
// observability tool like OpenTelemetry, Datadog, or Sentry APM.
// The functions are kept to demonstrate where performance tracking hooks
// would be placed in the application code.

import { redisClient, isRedisEnabled } from '@/lib/redis';
import { logger } from '@/lib/logger';
import { config } from '@/config/app-config';

if (isRedisEnabled) {
    logger.info('[Monitoring] Performance monitoring service is active (stub implementation).');
}

export async function trackAiQueryPerformance(query: string, durationMs: number): Promise<void> {
    if (!isRedisEnabled) return;
    try {
        const key = 'perf:ai_slow_log';
        const pipeline = redisClient.pipeline();
        pipeline.zadd(key, durationMs, `${new Date().toISOString()}|${query}`);
        pipeline.zremrangebyrank(key, 0, -101); // Keep only the top 100 slowest queries
        pipeline.expire(key, config.redis.ttl.performanceMetrics); // Set TTL to prevent memory leaks
        pipeline.incrbyfloat('perf:ai_total_duration', durationMs);
        pipeline.incr('perf:ai_total_count');
        await pipeline.exec();
    } catch (e) {
        logger.error('[Monitoring] Failed to track AI query performance:', e);
    }
}

export async function trackDbQueryPerformance(functionName: string, durationMs: number): Promise<void> {
    if (!isRedisEnabled) return;
    try {
        const key = `perf:db:${functionName}`;
        const pipeline = redisClient.pipeline();
        pipeline.zadd(`${key}:slow_log`, durationMs, `${new Date().toISOString()}`);
        pipeline.zremrangebyrank(`${key}:slow_log`, 0, -101);
        pipeline.expire(`${key}:slow_log`, config.redis.ttl.performanceMetrics);
        pipeline.incrbyfloat(`${key}:total_duration`, durationMs);
        pipeline.incr(`${key}:total_count`);
        await pipeline.exec();
    } catch (e) {
        logger.error(`[Monitoring] Failed to track DB query performance for ${functionName}:`, e);
    }
}
