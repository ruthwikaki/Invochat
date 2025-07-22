
import test from 'node:test';
import assert from 'node:assert/strict';

process.env.REDIS_URL = '';
const redisModule = await import('../../src/lib/redis');
const { rateLimit, isRedisEnabled } = redisModule;

test('rateLimit returns open state when redis disabled', async () => {
  assert.equal(isRedisEnabled, false);
  const result = await rateLimit('id', 'action', 5, 60);
  assert.equal(result.limited, false);
  assert.equal(result.remaining, 5);
});

test('rateLimit failClosed when redis disabled', async () => {
  const result = await rateLimit('id', 'action', 5, 60, true);
  assert.equal(result.limited, true);
  assert.equal(result.remaining, 0);
});
