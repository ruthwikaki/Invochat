
// Learn more about instrumentation hooks in Next.js:
// https://nextjs.org/docs/app/building-your-application/optimizing/instrumentation

import * as Sentry from '@sentry/nextjs';

export function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    Sentry.init({
        dsn: process.env.SENTRY_DSN,
        // Setting this option to true will print useful information to the console while you're setting up Sentry.
        debug: false,
    });
  }
 
  if (process.env.NEXT_RUNTIME === 'edge') {
    Sentry.init({
        dsn: process.env.SENTRY_DSN,
        // Setting this option to true will print useful information to the console while you're setting up Sentry.
        debug: false,
    });
  }
}
