import { generateCSRFToken, validateCSRFToken } from '../csrf';

describe('CSRF Protection', () => {
  describe('generateCSRFToken', () => {
    it('should generate a non-empty string token', () => {
      const token = generateCSRFToken();
      expect(typeof token).toBe('string');
      expect(token.length).toBeGreaterThan(0);
    });

    it('should generate different tokens on subsequent calls', () => {
      const token1 = generateCSRFToken();
      const token2 = generateCSRFToken();
      expect(token1).not.toBe(token2);
    });
  });

  describe('validateCSRFToken', () => {
    it('should return true for matching tokens', () => {
      const token = generateCSRFToken();
      expect(validateCSRFToken(token, token)).toBe(true);
    });

    it('should return false for non-matching tokens', () => {
      const token1 = generateCSRFToken();
      const token2 = generateCSRFToken();
      expect(validateCSRFToken(token1, token2)).toBe(false);
    });

    it('should return false for tokens of different lengths', () => {
      const token1 = 'abc';
      const token2 = 'abcd';
      expect(validateCSRFToken(token1, token2)).toBe(false);
    });

    it('should return false for invalid inputs', () => {
      const token = generateCSRFToken();
      expect(validateCSRFToken('', token)).toBe(false);
      expect(validateCSRFToken(token, '')).toBe(false);
      // @ts-expect-error
      expect(validateCSRFToken(null, token)).toBe(false);
      // @ts-expect-error
      expect(validateCSRFToken(token, undefined)).toBe(false);
    });
  });
});
