import { isError, getErrorMessage, logError } from '@/lib/error-handler';
import { logger } from '@/lib/logger';
import { describe, it, expect, vi } from 'vitest';

vi.mock('@/lib/logger', () => ({
  logger: {
    error: vi.fn(),
  },
}));

describe('isError', () => {
  it('should return true for Error objects', () => {
    expect(isError(new Error('test'))).toBe(true);
  });
  it('should return false for non-Error objects', () => {
    expect(isError('string')).toBe(false);
    expect(isError(123)).toBe(false);
    expect(isError({ a: 1 })).toBe(false);
    expect(isError(null)).toBe(false);
  });
});

describe('getErrorMessage', () => {
  it('should extract message from an Error object', () => {
    expect(getErrorMessage(new Error('This is a test'))).toBe('This is a test');
  });
  it('should return the string if a string is passed', () => {
    expect(getErrorMessage('A string error')).toBe('A string error');
  });
  it('should stringify an object', () => {
    expect(getErrorMessage({ error: 'object error' })).toContain('object error');
  });
  it('should handle null and undefined', () => {
    expect(getErrorMessage(null)).toBe('An unknown and non-stringifiable error occurred.');
    expect(getErrorMessage(undefined)).toBe('An unknown and non-stringifiable error occurred.');
  });
});

describe('logError', () => {
    it('should call the logger with the correct message and context', () => {
        const error = new Error('Test log error');
        const context = { userId: '123' };
        logError(error, context);

        expect(logger.error).toHaveBeenCalledWith('Test log error', expect.objectContaining({
            userId: '123',
            stack: expect.any(String),
        }));
    });
});
