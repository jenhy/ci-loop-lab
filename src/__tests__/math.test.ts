import { describe, it, expect } from 'vitest';
import { add, multiply } from '../math';

describe('add', () => {
  it('should add two positive numbers correctly', () => {
    expect(add(1, 2)).toBe(3);
  });

  it('should handle negative numbers', () => {
    expect(add(-1, 1)).toBe(0);
  });

  it('should handle zeros', () => {
    expect(add(0, 0)).toBe(0);
  });
});

describe('multiply', () => {
  it('should multiply two numbers', () => {
    expect(multiply(3, 4)).toBe(12);
  });

  it('should handle zero', () => {
    expect(multiply(5, 0)).toBe(0);
  });
});
