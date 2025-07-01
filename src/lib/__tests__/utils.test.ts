import { cn, linearRegression } from '../utils';

describe('cn utility', () => {
  it('merges tailwind classes without conflicts', () => {
    expect(cn('p-4', 'font-bold', 'p-2')).toBe('font-bold p-2');
  });

  it('handles conditional classes correctly', () => {
    const hasError = true;
    expect(cn('base', hasError && 'text-red-500')).toBe('base text-red-500');
    expect(cn('base', !hasError && 'text-red-500')).toBe('base');
  });

  it('handles falsy values gracefully', () => {
    expect(cn('a', false, 'b', 0, null, undefined, 'c')).toBe('a b c');
  });
});

describe('linearRegression', () => {
  it('calculates a simple positive slope', () => {
    const data = [{ x: 1, y: 1 }, { x: 2, y: 2 }, { x: 3, y: 3 }];
    const { slope, intercept } = linearRegression(data);
    expect(slope).toBe(1);
    expect(intercept).toBe(0);
  });

  it('calculates a negative slope', () => {
    const data = [{ x: 1, y: 3 }, { x: 2, y: 2 }, { x: 3, y: 1 }];
    const { slope, intercept } = linearRegression(data);
    expect(slope).toBe(-1);
    expect(intercept).toBe(4);
  });

  it('handles a flat line', () => {
    const data = [{ x: 1, y: 5 }, { x: 2, y: 5 }, { x: 3, y: 5 }];
    const { slope, intercept } = linearRegression(data);
    expect(slope).toBe(0);
    expect(intercept).toBe(5);
  });

  it('handles less than 2 data points', () => {
    const data = [{ x: 1, y: 10 }];
    const { slope, intercept } = linearRegression(data);
    expect(slope).toBe(0);
    expect(intercept).toBe(10);
  });

  it('handles empty data', () => {
    const data: { x: number; y: number }[] = [];
    const { slope, intercept } = linearRegression(data);
    // Based on the implementation, it will return NaN, which we check for and return 0.
    expect(slope).toBe(0);
    expect(intercept).toBe(0);
  });

  it('handles floating point numbers', () => {
    const data = [{ x: 1.5, y: 2.5 }, { x: 3.5, y: 4.5 }];
    const { slope, intercept } = linearRegression(data);
    expect(slope).toBeCloseTo(1);
    expect(intercept).toBeCloseTo(1);
  });
});
