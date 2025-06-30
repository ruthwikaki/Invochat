
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
// If any variable is missing or invalid, the server will refuse to start and
// log a clear error message.
const EnvSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().url({ message: "Must be a valid URL." }),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1, { message: "Is not set." }),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1, { message: "Is not set. This is required for server-side database operations." }),
  GOOGLE_API_KEY: z.string().min(1, { message: "Is not set. This is required for AI features." }),
  REDIS_URL: z.string().optional(),
});

const parsedEnv = EnvSchema.safeParse(process.env);

if (!parsedEnv.success) {
  const errorDetails = parsedEnv.error.flatten().fieldErrors;
  const errorMessages = Object.entries(errorDetails)
    .map(([key, messages]) => `  - ${key}: ${messages.join(', ')}`)
    .join('\n');
  
  // This provides a clear, developer-friendly error message in the server logs
  // and prevents the application from starting in a misconfigured state.
  throw new Error(`
=================================================================
❌ FATAL: Environment variable validation failed.
   Please check your .env file and ensure the following
   variables are set correctly:
${errorMessages}
=================================================================
`);
}
// --- End Validation ---


// Helper to parse numbers from env vars
const parseIntWithDefault = (value: string | undefined, defaultValue: number): number => {
    if (value === undefined) return defaultValue;
    const parsed = parseInt(value, 10);
    return isNaN(parsed) ? defaultValue : parsed;
};

const isProduction = process.env.NODE_ENV === 'production';

export const config = {
  app: {
    name: process.env.NEXT_PUBLIC_APP_NAME || 'InvoChat',
    url: process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:9003',
    environment: process.env.NODE_ENV || 'development',
  },
  ai: {
    model: process.env.AI_MODEL || 'googleai/gemini-1.5-flash',
    maxRetries: parseIntWithDefault(process.env.AI_MAX_RETRIES, 2),
    timeout: parseIntWithDefault(process.env.AI_TIMEOUT, 30000),
    historyLimit: parseIntWithDefault(process.env.AI_HISTORY_LIMIT, 10),
  },
  database: {
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
    queryLimit: parseIntWithDefault(process.env.DB_QUERY_LIMIT, 1000),
  },
  redis: {
    ttl: {
      dashboard: parseIntWithDefault(process.env.REDIS_TTL_DASHBOARD, 300), // 5 minutes
      aiQuery: parseIntWithDefault(process.env.REDIS_TTL_AI_QUERY, 3600), // 1 hour
    },
  },
  businessLogic: {
    deadStockDays: parseIntWithDefault(process.env.BL_DEAD_STOCK_DAYS, 90),
    fastMovingDays: parseIntWithDefault(process.env.BL_FAST_MOVING_DAYS, 30),
    overstockMultiplier: parseIntWithDefault(process.env.BL_OVERSTOCK_MULTIPLIER, 3),
    highValueThreshold: parseIntWithDefault(process.env.BL_HIGH_VALUE_THRESHOLD, 1000),
  },
  chat: {
    quickActions: [
      "What were my top 5 products by revenue last month?",
      "Show a pie chart of inventory value by category",
      "Which suppliers provide items that are currently low on stock?",
      "Forecast sales for the next quarter",
    ],
  },
  ui: {
    sidebarCookieMaxAge: parseIntWithDefault(process.env.UI_SIDEBAR_COOKIE_MAX_AGE, 60 * 60 * 24 * 7), // 7 days
  }
};


// A type alias for convenience
export type AppConfig = typeof config;
