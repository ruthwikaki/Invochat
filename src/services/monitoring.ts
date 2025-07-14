
'use server';

// This monitoring service is a stub for a more robust implementation.
// In a production environment, this would be replaced with a proper
// observability tool like OpenTelemetry, Datadog, or Sentry APM.
// The functions are kept to demonstrate where performance tracking hooks
// would be placed in the application code.

import { redisClient, isRedisEnabled } from '@/lib/redis';
import { logger } from '@/lib/logger';

if (isRedisEnabled) {
    logger.info('[Monitoring] Performance monitoring service is active (stub implementation).');
}

export async function trackAiQueryPerformance(query: string, durationMs: number): Promise<void> {
    if (!isRedisEnabled) return;
    try {
        const pipeline = redisClient.pipeline();
        pipeline.zadd('perf:ai_slow_log', durationMs, `${new Date().toISOString()}|${query}`);
        pipeline.zremrangebyrank('perf:ai_slow_log', 0, -101);
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
        const pipeline = redisClient.pipeline();
        pipeline.zadd('perf:db_slow_log', durationMs, `${new Date().toISOString()}|${functionName}`);
        pipeline.zremrangebyrank('perf:db_slow_log', 0, -101);
        pipeline.incrbyfloat(`perf:db:${functionName}:total_duration`, durationMs);
        pipeline.incr(`perf:db:${functionName}:total_count`);
        await pipeline.exec();
    } catch (e) {
        logger.error(`[Monitoring] Failed to track DB query performance for ${functionName}:`, e);
    }
}
