
import test from 'node:test';
import assert from 'node:assert/strict';
import { logger } from '../../src/lib/logger';

test('logger.info prints message', () => {
  const msgs: string[] = [];
  const orig = console.info;
  console.info = (msg: string) => { msgs.push(msg); };
  logger.info('hello');
  console.info = orig;
  assert.ok(msgs.some(m => m.includes('hello')));
});
