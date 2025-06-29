
import Redis from 'ioredis';
import { logger } from './logger';

let redis: Redis | null = null;

// Mock client to be used when Redis is not configured.
// It mimics the Redis methods we use so the app doesn't crash.
const mockRedisClient = {
    get: async (key: string) => null,
    set: async (key: string, value: string, ...args: any[]) => 'OK' as const,
    del: async (...keys: string[]) => 1 as const,
    pipeline: () => mockRedisClient, // Return self for pipeline chaining
    zremrangebyscore: () => mockRedisClient,
    zadd: () => mockRedisClient,
    expire: () => mockRedisClient,
    exec: async () => [[null, 0], [null, 0], [null, 0]], // Mock exec response
    ping: async () => 'PONG' as const,
    incr: async (key: string) => 1,
    incrbyfloat: async (key: string, inc: number) => String(inc),
    zcard: async (key: string) => 0,
};

if (process.env.REDIS_URL) {
    logger.info('[Redis] Attempting to connect to Redis instance...');
    try {
        const client = new Redis(process.env.REDIS_URL, {
            maxRetriesPerRequest: 2,
            connectTimeout: 5000,
        });

        client.on('connect', () => {
            logger.info('[Redis] Connection established.');
        });

        client.on('error', (err) => {
            // Log the error. The client will attempt to reconnect automatically.
            // Calls to redis during this time will fail and should be handled by try/catch blocks.
            logger.error(`[Redis] Connection error: ${err.message}. The client will attempt to reconnect.`);
        });
        
        redis = client;

    } catch (e: any) {
        logger.error(`[Redis] Failed to initialize client: ${e.message}`);
    }
} else {
    logger.warn('[Redis] REDIS_URL is not set. Caching and rate limiting are disabled.');
}

// If connection failed or was not configured, use the mock client.
export const redisClient = redis || mockRedisClient;
export const isRedisEnabled = !!redis;

/**
 * Invalidates specific cache types for a given company.
 * This function is fire-and-forget; it logs errors but does not throw them,
 * ensuring that cache invalidation failures do not break critical application flows.
 * @param companyId The UUID of the company whose cache should be invalidated.
 * @param types An array of cache types to invalidate (e.g., 'dashboard', 'alerts').
 */
export async function invalidateCompanyCache(companyId: string, types: ('dashboard' | 'alerts' | 'deadstock' | 'suppliers')[]): Promise<void> {
    if (!isRedisEnabled || !redis) {
        return;
    }
    
    // Construct the full cache keys to be deleted.
    const keysToInvalidate = types.map(type => `company:${companyId}:${type}`);
    
    if (keysToInvalidate.length > 0) {
        try {
            logger.info(`[Redis] Invalidating cache for company ${companyId}. Keys: ${keysToInvalidate.join(', ')}`);
            await redis.del(keysToInvalidate);
        } catch (e) {
            logger.error(`[Redis] Cache invalidation failed for company ${companyId}:`, e);
        }
    }
}

/**
 * Applies a rate limit for a given identifier and action using a sliding window log algorithm.
 * @param identifier A unique string for the user/IP being rate-limited.
 * @param action A descriptor for the action being limited (e.g., 'auth', 'ai_chat').
 * @param limit The maximum number of requests allowed in the window.
 * @param windowSeconds The duration of the window in seconds.
 * @returns A promise resolving to an object with `limited` (boolean) and `remaining` (number) properties.
 */
export async function rateLimit(
    identifier: string,
    action: string,
    limit: number,
    windowSeconds: number
): Promise<{ limited: boolean; remaining: number }> {
    if (!isRedisEnabled || !redis) {
        return { limited: false, remaining: limit };
    }

    try {
        const key = `rate_limit:${action}:${identifier}`;
        const now = Date.now();
        const windowStart = now - windowSeconds * 1000;

        const pipeline = redis.pipeline();
        // Remove timestamps that are older than the window
        pipeline.zremrangebyscore(key, 0, windowStart);
        // Add the current request's timestamp
        pipeline.zadd(key, now, now.toString());
        // Get the count of all requests within the window
        pipeline.zcard(key);
        // Set an expiry on the key to clean up old data automatically
        pipeline.expire(key, windowSeconds);

        const results = await pipeline.exec();
        
        // results will be an array of tuples, e.g., [[null, 1], [null, 1], [null, 5], [null, 1]]
        // We need the result from zcard, which is the 3rd command (index 2)
        const requestCountResult = results ? results[2] : null;

        if (!requestCountResult || requestCountResult[0]) { // Check for error in the tuple
            throw new Error('Failed to get request count from Redis pipeline.');
        }

        const requestCount = requestCountResult[1] as number;
        
        const isLimited = requestCount > limit;
        const remaining = isLimited ? 0 : limit - requestCount;

        return { limited: isLimited, remaining };
    } catch (error) {
        logger.error(`[Redis] Rate limiting failed for action "${action}"`, error);
        // Fail open: If Redis fails, don't block the request.
        return { limited: false, remaining: limit };
    }
}
