import test from 'node:test';
import assert from 'node:assert/strict';

import { cn, linearRegression, formatCentsAsCurrency } from '../../src/lib/utils';

test('cn merges class names', () => {
  assert.equal(cn('foo', { bar: true, baz: false }), 'foo bar');
});

test('linearRegression calculates slope and intercept', () => {
  const data = [ { x: 1, y: 2 }, { x: 2, y: 4 } ];
  const result = linearRegression(data);
  assert.equal(result.slope.toFixed(1), '2.0');
  assert.equal(result.intercept.toFixed(1), '0.0');
});

test('formatCentsAsCurrency handles values', () => {
  assert.equal(formatCentsAsCurrency(1234), '$12.34');
  assert.equal(formatCentsAsCurrency(null), '$0.00');
  assert.equal(formatCentsAsCurrency(undefined), '$0.00');
});
