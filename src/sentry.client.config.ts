
// This file configures the Sentry browser client for error reporting.
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  // Setting this option to true will print useful information to the console while you're setting up Sentry.
  debug: false,

  // You can remove this option if you're not planning to use the Sentry Replay feature.
  replaysOnErrorSampleRate: 1.0,

  // This sets the sample rate to be 10%. You may want this to be 100% while
  // in development and sample it in production
  replaysSessionSampleRate: 0.1,
});

