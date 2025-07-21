
import Redis from 'ioredis';
import { logger } from './logger';
import { getErrorMessage } from './error-handler';
import { config } from '@/config/app-config';

// A private, module-level variable to hold the singleton instance.
let redis: Redis | null = null;
let isInitializing = false;

// Mock client to be used when Redis is not configured.
// It mimics the Redis methods we use so the app doesn't crash.
const mockRedisClient = {
    get: async (_key: string) => null,
    set: async (_key: string, _value: string, ..._args: unknown[]) => 'OK' as const,
    del: async (..._keys: string[]) => 1 as const,
    pipeline: function () { // The pipeline function needs to return an object with the chained methods
        const pipeline = {
            zremrangebyscore: () => pipeline,
            zadd: () => pipeline,
            zcard: () => pipeline,
            expire: () => pipeline,
            exec: async () => [[null, 0], [null, 0], [null, 0], [null, 1]],
        };
        return pipeline as unknown as Redis.Pipeline;
    },
    ping: async () => 'PONG' as const,
    incr: async (_key: string) => 1,
    incrbyfloat: async (_key: string, inc: number) => String(inc),
    zcard: async (_key: string) => 0,
};


/**
 * Initializes and returns a singleton Redis client instance.
 * This function is designed to be safe to call multiple times, but it will
 * only ever create one underlying Redis connection.
 */
function initializeRedis(): Redis | null {
    // If an instance already exists, just return it. This is the most common path.
    if (redis) {
        return redis;
    }

    // Prevent re-entrant calls while the first initialization is in progress.
    if (isInitializing) {
        logger.warn('[Redis] Initialization already in progress, returning null for this call.');
        return null;
    }

    if (!process.env.REDIS_URL) {
        // No need to log here; the final export block will handle it.
        return null;
    }
    
    isInitializing = true;
    logger.info('[Redis] Initializing new singleton Redis client...');

    try {
        const client = new Redis(process.env.REDIS_URL, {
            maxRetriesPerRequest: 3,
            connectTimeout: 10000,
            // As recommended, implement an exponential backoff retry strategy to prevent "reconnect storms".
            retryStrategy(times) {
                const delay = Math.min(times * 100, 5000); 
                logger.warn(`[Redis] Reconnecting... attempt ${times}. Retrying in ${delay}ms`);
                return delay;
            },
        });

        client.on('connect', () => {
            logger.info('[Redis] Connection established.');
        });

        client.on('error', (err) => {
            logger.error(`[Redis] Connection error: ${err.message}. The client will attempt to reconnect based on the retry strategy.`);
        });
        
        client.on('close', () => {
            logger.warn('[Redis] Connection closed.');
        });

        // Cache the singleton instance.
        redis = client;
        return redis;
    } catch (e) {
        logger.error(`[Redis] Failed to initialize client instance: ${getErrorMessage(e)}`);
        return null; // Return null on catastrophic failure
    } finally {
        isInitializing = false;
    }
}


// --- SINGLETON INITIALIZATION ---
// This block ensures that we only ever have one Redis client for the lifetime of the process.
const globalForRedis = global as unknown as { redis: Redis | null };

if (process.env.NODE_ENV !== 'production') {
    // In development, hot-reloading can cause modules to be re-evaluated, leading to new instances.
    // We store the instance on the global object to persist it across reloads.
    if (!globalForRedis.redis) {
        globalForRedis.redis = initializeRedis();
    }
    redis = globalForRedis.redis;
} else {
    // In production, the module is only evaluated once per process.
    redis = initializeRedis();
}

if (!redis) {
    logger.warn('[Redis] Singleton client not initialized. Caching and rate limiting are disabled.');
}
// ------------------------------------


// Export the singleton instance (or the mock if initialization failed).
export const redisClient = redis || (mockRedisClient as unknown as Redis);
export const isRedisEnabled = !!redis;

/**
 * Invalidates specific cache types for a given company.
 * This function is fire-and-forget; it logs errors but does not throw them,
 * ensuring that cache invalidation failures do not break critical application flows.
 * @param companyId The UUID of the company whose cache should be invalidated.
 * @param types An array of cache types to invalidate (e.g., 'dashboard', 'alerts').
 */
export async function invalidateCompanyCache(companyId: string, types: ('dashboard' | 'alerts' | 'deadstock' | 'suppliers')[]): Promise<void> {
    if (!isRedisEnabled) {
        return;
    }
    
    const keysToInvalidate = types.map(type => `company:${companyId}:${type}`);
    
    if (keysToInvalidate.length > 0) {
        try {
            logger.info(`[Redis] Invalidating cache for company ${companyId}. Keys: ${keysToInvalidate.join(', ')}`);
            await redisClient.del(keysToInvalidate);
        } catch (e) {
            logger.error(`[Redis] Cache invalidation failed for company ${companyId}:`, e);
        }
    }
}


export async function testRedisConnection() {
    if (!isRedisEnabled) {
        return { success: false, isConfigured: false, error: 'Redis is not configured in environment variables.' };
    }
    try {
        const response = await redisClient.ping();
        if (response !== 'PONG') {
            throw new Error('Redis did not respond with PONG.');
        }
        return { success: true, isConfigured: true };
    } catch (e) {
        return { success: false, isConfigured: true, error: getErrorMessage(e) };
    }
}

/**
 * Applies a rate limit for a given identifier and action using a sliding window log algorithm.
 * @param identifier A unique string for the user/IP being rate-limited.
 * @param action A descriptor for the action being limited (e.g., 'auth', 'ai_chat').
 * @param limit The maximum number of requests allowed in the window.
 * @param windowSeconds The duration of the window in seconds.
 * @param failClosed If true, the rate limiter will block requests if Redis is unavailable. Defaults to false.
 * @returns A promise resolving to an object with `limited` (boolean) and `remaining` (number) properties.
 */
export async function rateLimit(
    identifier: string,
    action: string,
    limit: number,
    windowSeconds: number,
    failClosed: boolean = false
): Promise<{ limited: boolean; remaining: number }> {
    if (!isRedisEnabled) {
        // If Redis is not enabled, fail open or closed based on the flag.
        return { limited: failClosed, remaining: failClosed ? 0 : limit };
    }

    try {
        const key = `rate_limit:${action}:${identifier}`;
        const now = Date.now();
        const windowStart = now - windowSeconds * 1000;

        const pipeline = redisClient.pipeline();
        // Remove timestamps that are older than the window
        pipeline.zremrangebyscore(key, 0, windowStart);
        // Add the current request's timestamp
        pipeline.zadd(key, now, now.toString());
        // Get the count of all requests within the window
        pipeline.zcard(key);
        // Set an expiry on the key to clean up old data automatically, preventing memory leaks.
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
        logger.error(`[Redis] Rate limiting failed for action "${action}". Failing ${failClosed ? 'closed' : 'open'}.`, error);
        // If Redis fails, fail open or closed based on the flag. This is a critical design choice.
        return { limited: failClosed, remaining: failClosed ? 0 : limit };
    }
}
