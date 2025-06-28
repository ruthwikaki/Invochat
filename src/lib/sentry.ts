
'use server';

/**
 * @fileoverview Sentry configuration and error capturing.
 * This file initializes Sentry if a DSN is provided and exports
 * a utility function to capture errors throughout the application.
 */
import * as Sentry from '@sentry/nextjs';
import { logger } from './logger';
import { config } from '@/config/app-config';

const SENTRY_DSN = config.monitoring.sentryDsn;

let isSentryEnabled = false;

if (SENTRY_DSN) {
  try {
    Sentry.init({
      dsn: SENTRY_DSN,
      // We recommend adjusting this value in production, or using tracesSampler
      // for finer control
      tracesSampleRate: 1.0,

      // Setting this option to true will print useful information to the console while you're setting up Sentry.
      debug: false,
    });
    isSentryEnabled = true;
    logger.info('[Sentry] Error tracking enabled.');
  } catch (error: any) {
    logger.error('[Sentry] Failed to initialize:', error.message);
  }
} else {
  logger.warn('[Sentry] SENTRY_DSN is not set. Error tracking is disabled.');
}

/**
 * Captures an error and sends it to Sentry if enabled.
 * Also logs the error to the console for local debugging.
 * @param error The error object to capture.
 * @param context An optional object containing additional context.
 */
export function captureError(error: any, context?: Record<string, any>) {
  // Always log the error locally for immediate visibility.
  logger.error(context ? (context.source || 'Generic Error') : 'Generic Error', { error, context });

  if (isSentryEnabled) {
    Sentry.captureException(error, {
      extra: context,
    });
  }
}
