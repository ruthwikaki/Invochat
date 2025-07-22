
import test from 'node:test';
import assert from 'node:assert/strict';
import { reducer } from '../../src/hooks/use-toast';

const baseToast = { id: '1', title: 'hi', open: true } as any;

test('reducer adds toast', () => {
  const state = { toasts: [] };
  const next = reducer(state, { type: 'ADD_TOAST', toast: baseToast });
  assert.equal(next.toasts.length, 1);
});

test('reducer dismisses toast', () => {
  const state = { toasts: [baseToast] };
  const next = reducer(state, { type: 'DISMISS_TOAST', toastId: '1' });
  assert.equal(next.toasts[0].open, false);
});
