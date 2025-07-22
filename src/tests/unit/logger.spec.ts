import { logger } from '../../lib/logger';
import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';

describe('logger', () => {
  const consoleInfoSpy = vi.spyOn(console, 'info').mockImplementation(() => {});
  const consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('should log info messages to console.info', () => {
    logger.info('Test info message', { data: 1 });
    expect(consoleInfoSpy).toHaveBeenCalledWith(expect.stringContaining('[INFO] - Test info message'), { data: 1 });
  });

  it('should log error messages to console.error', () => {
    logger.error('Test error message', { error: 'test' });
    expect(consoleErrorSpy).toHaveBeenCalledWith(expect.stringContaining('[ERROR] - Test error message'), { error: 'test' });
  });
});
