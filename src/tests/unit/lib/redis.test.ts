
import { rateLimit, isRedisEnabled } from '@/lib/redis';
import { describe, it, expect, vi } from 'vitest';

// Mock redis client for tests
vi.mock('ioredis', () => {
    const Redis = vi.fn(() => ({
      pipeline: vi.fn(() => ({
        zremrangebyscore: vi.fn().mockReturnThis(),
        zadd: vi.fn().mockReturnThis(),
        zcard: vi.fn().mockReturnThis(),
        expire: vi.fn().mockReturnThis(),
        exec: vi.fn().mockResolvedValue([[null, 0], [null, 1], [null, 1], [null, 1]]),
      })),
      ping: vi.fn().mockResolvedValue('PONG'),
    }));
    return { default: Redis };
});


// We conditionally run these tests because they require a Redis instance.
// In a CI environment, this might be mocked or connected to a real test instance.
const RUN_REDIS_TESTS = isRedisEnabled;

describe.skipIf(!RUN_REDIS_TESTS)('rateLimit', () => {
    
  it('should allow requests below the limit', async () => {
    const identifier = `test-user-${Date.now()}`;
    const result = await rateLimit(identifier, 'test_action', 5, 60);
    expect(result.limited).toBe(false);
    expect(result.remaining).toBe(4);
  });

});
