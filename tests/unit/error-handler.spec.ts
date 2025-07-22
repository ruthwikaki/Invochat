import test from 'node:test';
import assert from 'node:assert/strict';
import { isError, getErrorMessage } from '../../src/lib/error-handler';

test('isError returns true for Error objects', () => {
  assert.ok(isError(new Error('boom')));
});

test('isError returns false for non Error', () => {
  assert.equal(isError('no'), false);
});

test('getErrorMessage handles strings', () => {
  assert.equal(getErrorMessage('msg'), 'msg');
});


test('getErrorMessage handles objects', () => {
  const obj = { foo: 'bar' } as unknown as Error;
  const msg = getErrorMessage(obj);
  assert.ok(msg.includes('foo'));
});
