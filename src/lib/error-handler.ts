
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
    // Attempt to stringify, but handle potential circular references
    return JSON.stringify(error, null, 2);
  } catch {
    return 'An unknown and non-stringifiable error occurred.';
  }
}

/**
 * A type-safe error logger. It automatically captures the stack trace if available.
 * @param error The error to log.
 * @param context Additional context for the error log.
 */
export function logError(error: unknown, context: Record<string, unknown> = {}) {
    const message = getErrorMessage(error);
    
    // Construct a log object with context and error details
    const logObject = {
        ...context,
        // If the error is an actual Error object, include its stack for better debugging.
        ...(isError(error) && { stack: error.stack }),
    };

    // Use the centralized logger
    logger.error(message, logObject);
}
