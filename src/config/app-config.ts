
/**
 * @fileoverview Centralized, environment-aware configuration for InvoChat.
 *
 * This file consolidates all external configuration, pulling from environment
 * variables with sensible defaults. This is crucial for security and for

 * operating the application across different environments (dev, staging, prod).
 */
import { config as dotenvConfig } from 'dotenv';
import { z } from 'zod';

// Force load .env variables at the earliest point.
dotenvConfig();


// --- Environment Variable Validation ---
// This schema validates all critical environment variables on application startup.
// If any variable is missing or invalid, the app will render an error page.
const EnvSchema = z.object({
  SITE_URL: z.string().url({ message: "Must be a valid URL." }),
  NEXT_PUBLIC_SITE_URL: z.string().url({ message: "Must be a valid URL." }),
  NEXT_PUBLIC_SUPABASE_URL: z.string().url({ message: "Must be a valid URL." }),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1, { message: "Is not set." }),
  SUPABASE_URL: z.string().url({ message: "Must be a valid URL." }),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1, { message: "Is not set. This is required for server-side database operations." }),
  GOOGLE_API_KEY: z.string().min(1, { message: "Is not set. This is required for AI features." }),
  REDIS_URL: z.string().optional(),
  ENCRYPTION_KEY: z.string().length(64, { message: "Must be a 64-character hex string (32 bytes)."}),
  HEALTH_CHECK_API_KEY: z.string().min(1, { message: "Is not set. Required for health check endpoint security."}),
  SHOPIFY_WEBHOOK_SECRET: z.string().optional(),
  WOOCOMMERCE_WEBHOOK_SECRET: z.string().optional(),
  RESEND_API_KEY: z.string().optional(),
  EMAIL_FROM: z.string().email().optional(),
  EMAIL_TEST_RECIPIENT: z.string().email().optional(),
});

// Export the result of the validation to be checked in the root layout.
export const envValidation = EnvSchema.safeParse(process.env);

// --- End Validation ---


// Helper to parse numbers from env vars
const parseIntWithDefault = (value: string | undefined, defaultValue: number): number => {
    if (value === undefined) return defaultValue;
    const parsed = parseInt(value, 10);
    return isNaN(parsed) ? defaultValue : parsed;
};

const parseFloatWithDefault = (value: string | undefined, defaultValue: number): number => {
    if (value === undefined) return defaultValue;
    const parsed = parseFloat(value);
    return isNaN(parsed) ? defaultValue : parsed;
};

export const config = {
  app: {
    name: process.env.APP_NAME || 'ARVO',
    url: envValidation.success ? envValidation.data.SITE_URL : 'http://localhost:3000',
    environment: process.env.NODE_ENV,
  },
  ai: {
    model: process.env.AI_MODEL || 'googleai/gemini-1.5-flash',
    historyLimit: 10,
    maxOutputTokens: 2048,
    timeoutMs: 30000, // 30 second timeout for AI calls
  },
  ratelimit: {
    auth: 5, // 5 requests per minute
    ai: 20, // 20 requests per minute
    import: 10, // 10 imports per hour
    sync: 10, // 10 syncs per hour
    connect: 5, // 5 integration connection attempts per hour
  },
  import: {
    maxFileSizeMB: 10,
    batchSize: 500,
  },
  integrations: {
    syncDelayMs: 500, // Delay between API calls during sync
    webhookReplayWindowSeconds: 300, // 5 minutes
  },
  chat: {
    quickActions: [
      "What should I order today?",
      "What's not selling?",
      "Show me dead stock",
      "Top products this month",
    ],
  },
  redis: {
    ttl: {
        aiQuery: 3600, // 1 hour
        performanceMetrics: 86400, // 24 hours
    }
  }
};

// A type alias for convenience
export type AppConfig = typeof config;
