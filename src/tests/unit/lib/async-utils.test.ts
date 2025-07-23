
import { withTimeout } from '@/lib/async-utils';
import { describe, it, expect, vi } from 'vitest';

describe('withTimeout', () => {
  it('should resolve with the promise value if it resolves within the timeout', async () => {
    const fastPromise = new Promise(resolve => setTimeout(() => resolve('success'), 10));
    await expect(withTimeout(fastPromise, 20)).resolves.toBe('success');
  });

  it('should reject with a timeout error if the promise takes too long', async () => {
    const slowPromise = new Promise(resolve => setTimeout(() => resolve('should not happen'), 30));
    await expect(withTimeout(slowPromise, 20)).rejects.toThrow('Operation timed out.');
  });

  it('should use the custom error message when provided', async () => {
    const slowPromise = new Promise(resolve => setTimeout(resolve, 30));
    const customMessage = 'Custom timeout message';
    await expect(withTimeout(slowPromise, 20, customMessage)).rejects.toThrow(customMessage);
  });

  it('should reject with the original promise error if it rejects before the timeout', async () => {
    const failingPromise = new Promise((_, reject) => setTimeout(() => reject(new Error('original error')), 10));
    await expect(withTimeout(failingPromise, 20)).rejects.toThrow('original error');
  });
});
