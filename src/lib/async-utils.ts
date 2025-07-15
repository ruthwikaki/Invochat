
/**
 * @fileoverview Utilities for handling asynchronous operations, like timeouts.
 */

/**
 * Wraps a promise with a timeout. If the promise does not resolve or reject
 * within the given time, the wrapper promise will reject with a timeout error.
 *
 * @param promise The promise to wrap.
 * @param ms The timeout duration in milliseconds.
 * @param errorMessage The error message to use for the timeout rejection.
 * @returns A new promise that resolves/rejects with the original promise, or rejects on timeout.
 */
export const withTimeout = <T,>(
  promise: Promise<T>,
  ms: number,
  errorMessage = 'Operation timed out.'
): Promise<T> => {
  const timeout = new Promise<never>((_, reject) => {
    setTimeout(() => {
      reject(new Error(errorMessage));
    }, ms);
  });

  return Promise.race([promise, timeout]);
};
