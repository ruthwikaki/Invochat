import test from 'node:test';
import assert from 'node:assert/strict';
import { withTimeout } from '../../src/lib/async-utils';

// Basic unit tests for withTimeout utility

test('withTimeout resolves before timeout', async () => {
  const result = await withTimeout(Promise.resolve('ok'), 1000);
  assert.strictEqual(result, 'ok');
});

test('withTimeout rejects after timeout', async () => {
  try {
    await withTimeout(new Promise(res => setTimeout(res, 50)), 10);
    assert.fail('Expected timeout');
  } catch (e) {
    assert.match(String(e), /Operation timed out/);
  }
});
