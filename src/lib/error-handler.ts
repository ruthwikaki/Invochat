
/**
 * @fileoverview Centralized, type-safe error handling utilities.
 */
import { logger } from './logger';

/**
 * Type guard to check if an unknown value is an Error object.
 * @param error The value to check.
 * @returns True if the value is an Error, false otherwise.
 */
export function isError(error: unknown): error is Error {
  return error instanceof Error;
}

/**
 * Extracts a message from an unknown error type.
 * @param error The error to process.
 * @returns A string representing the error message.
 */
export function getErrorMessage(error: unknown): string {
  if (isError(error)) {
    return error.message;
  }
  if (typeof error === 'string') {
    return error;
  }
  try {
    return JSON.stringify(error);
  } catch {
    return 'An unknown error occurred.';
  }
}

/**
 * A type-safe error logger.
 * @param error The error to log.
 * @param context Additional context for the error log.
 */
export function logError(error: unknown, context: Record<string, unknown> = {}) {
    const message = getErrorMessage(error);
    logger.error(message, {
        ...context,
        errorObject: isError(error) ? error : undefined,
    });
}
