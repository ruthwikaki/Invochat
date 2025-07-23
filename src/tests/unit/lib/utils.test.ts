
import { describe, it, expect } from 'vitest'
import { cn, formatCentsAsCurrency } from '@/lib/utils'

describe('utils', () => {
  describe('cn', () => {
    it('should merge class names correctly', () => {
      expect(cn('class1', 'class2')).toBe('class1 class2')
      expect(cn('class1', undefined, 'class2')).toBe('class1 class2')
    })
  })

  describe('formatCentsAsCurrency', () => {
    it('should format currency correctly', () => {
      expect(formatCentsAsCurrency(123456)).toBe('$1,234.56')
      expect(formatCentsAsCurrency(0)).toBe('$0.00')
    })
  })
})
