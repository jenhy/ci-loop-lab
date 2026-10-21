/**
 * 加法函数 — 回归模拟的目标代码
 *
 * 正常状态: return a + b
 * 回归状态: return a + b + 1（由 inject-regression.sh 注入）
 */
export function add(a: number, b: number): number {
  return a + b; // BUG: injected regression
}

export function multiply(a: number, b: number): number {
  return a * b;
}
