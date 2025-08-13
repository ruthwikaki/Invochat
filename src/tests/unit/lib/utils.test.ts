
import { describe, it, expect } from 'vitest';
import { cn, formatCentsAsCurrency } from '@/lib/utils';

describe('utils', () => {
  describe('cn', () => {
    it('should merge class names correctly', () => {
      expect(cn('class1', 'class2')).toBe('class1 class2');
      expect(cn('class1', undefined, 'class2')).toBe('class1 class2');
    });
  });

  describe('formatCentsAsCurrency', () => {
    it('should format currency correctly from cents', () => {
      expect(formatCentsAsCurrency(123456)).toBe('$1,234.56');
      expect(formatCentsAsCurrency(0)).toBe('$0.00');
      expect(formatCentsAsCurrency(10)).toBe('$0.10');
      expect(formatCentsAsCurrency(99)).toBe('$0.99');
      expect(formatCentsAsCurrency(100)).toBe('$1.00');
    });

    it('should handle null and undefined values', () => {
        expect(formatCentsAsCurrency(null)).toBe('$0.00');
        expect(formatCentsAsCurrency(undefined)).toBe('$0.00');
    });
  });
});

