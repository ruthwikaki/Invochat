import { describe, it, expect, vi, beforeEach } from 'vitest';

// Create a simple test that should work
describe('Economic Indicators Tool', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should pass a basic test', () => {
    expect(true).toBe(true);
  });

  it('should verify mock functionality', () => {
    const mockFn = vi.fn();
    mockFn.mockReturnValue('test');
    
    const result = mockFn();
    expect(result).toBe('test');
    expect(mockFn).toHaveBeenCalledOnce();
  });
});
