import Redis from 'ioredis';

let redis: Redis | null = null;

// Mock client to be used when Redis is not configured.
// It mimics the Redis methods we use so the app doesn't crash.
const mockRedisClient = {
    get: async (key: string) => null,
    set: async (key: string, value: string, ...args: any[]) => 'OK' as const,
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
