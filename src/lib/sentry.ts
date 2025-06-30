/**
 * @fileoverview This file is intentionally left blank. The Sentry integration has been temporarily
 * removed to resolve critical dependency installation issues.
 */
import { logger } from './logger';
import { getErrorMessage } from './error-handler';

// This is a stub function to prevent build errors where captureError was imported.
export async function captureError(error: unknown, context?: Record<string, unknown>) {
  logger.error(
    (context?.source as string) || 'Generic Error (Sentry Disabled)',
    { error: getErrorMessage(error), context }
  );
}
