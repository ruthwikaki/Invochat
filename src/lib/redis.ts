import Redis from 'ioredis';

let redis: Redis | null = null;

// Mock client to be used when Redis is not configured.
// It mimics the Redis methods we use so the app doesn't crash.
const mockRedisClient = {
    get: async (key: string) => null,
    set: async (key: string, value: string, ...args: any[]) => 'OK' as const,
    del: async (...keys: string[]) => 1 as const,
};

if (process.env.REDIS_URL) {
    console.log('[Redis] Attempting to connect to Redis instance...');
    try {
        const client = new Redis(process.env.REDIS_URL, {
            maxRetriesPerRequest: 2,
            connectTimeout: 5000,
        });

        client.on('connect', () => {
            console.log('[Redis] Connection established.');
        });

        client.on('error', (err) => {
            console.error(`[Redis] Connection error: ${err.message}. Caching will be disabled for this session.`);
            // In case of error, we can switch to the mock client to prevent app crashes on subsequent calls
            redis = null; 
        });
        
        redis = client;

    } catch (e: any) {
        console.error(`[Redis] Failed to initialize client: ${e.message}`);
    }
} else {
    console.warn('[Redis] REDIS_URL is not set. Caching is disabled.');
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
            console.log(`[Redis] Invalidating cache for company ${companyId}. Keys: ${keysToInvalidate.join(', ')}`);
            await redis.del(keysToInvalidate);
        } catch (e) {
            console.error(`[Redis] Cache invalidation failed for company ${companyId}:`, e);
        }
    }
}
