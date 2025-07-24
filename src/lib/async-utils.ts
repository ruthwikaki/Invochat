

export async function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  timeoutMessage = 'Operation timed out.'
): Promise<T> {
  const timeoutPromise = new Promise<never>((_, reject) => {
    setTimeout(() => reject(new Error(timeoutMessage)), timeoutMs)
  })
  
  return Promise.race([promise, timeoutPromise])
}

export function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

export async function retry<T>(
  fn: () => Promise<T>,
  options: { maxAttempts?: number; delayMs?: number, onRetry?: (error: Error, attempt: number) => void } = {}
): Promise<T> {
  const { maxAttempts = 3, delayMs = 1000, onRetry } = options;
  let lastError: Error | undefined;
  
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn()
    } catch (error) {
      lastError = error as Error
      if (attempt === maxAttempts) break;

      if (onRetry) {
        onRetry(lastError, attempt);
      }
      
      const exponentialDelay = delayMs * Math.pow(2, attempt - 1);
      await delay(exponentialDelay);
    }
  }
  
  throw lastError!;
}
