import { rateLimit, isRedisEnabled } from '../../lib/redis';
import { describe, it, expect } from 'vitest';

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

  it('should block requests exceeding the limit', async () => {
    const identifier = `test-user-${Date.now()}`;
    const action = 'rate_limit_exceed_test';
    const limit = 3;

    for (let i = 0; i < limit; i++) {
        await rateLimit(identifier, action, limit, 60);
    }

    const result = await rateLimit(identifier, action, limit, 60);
    expect(result.limited).toBe(true);
    expect(result.remaining).toBe(0);
  });

});
