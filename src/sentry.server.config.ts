
// This file configures the Sentry server client for error reporting.
// It runs on the server-side only and is automatically called by Sentry's Next.js SDK.
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  // Setting this option to true will print useful information to the console while you're setting up Sentry.
  debug: false,
});
