/**
 * @fileoverview This file is intentionally left blank. The Sentry integration has been temporarily
 * removed to resolve critical dependency installation issues.
 */
import { logger } from './logger';

// This is a stub function to prevent build errors where captureError was imported.
export async function captureError(error: any, context?: Record<string, any>) {
  logger.error(
    context?.source || 'Generic Error (Sentry Disabled)',
    { error, context }
  );
}
