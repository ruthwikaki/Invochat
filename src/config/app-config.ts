
/**
 * @fileoverview Centralized, environment-aware configuration for InvoChat.
 *
 * This file consolidates all external configuration, pulling from environment
 * variables with sensible defaults. This is crucial for security and for
 * operating the application across different environments (dev, staging, prod).
 */
import { config as dotenvConfig } from 'dotenv';
import { z } from 'zod';
import { SMB_CONFIG } from './smb';

// Force load .env variables at the earliest point.
dotenvConfig();


// --- Environment Variable Validation ---
// This schema validates all critical environment variables on application startup.
// If any variable is missing or invalid, the app will render an error page.
const EnvSchema = z.object({
  NEXT_PUBLIC_SITE_URL: z.string().url({ message: "Must be a valid URL." }),
  NEXT_PUBLIC_SUPABASE_URL: z.string().url({ message: "Must be a valid URL." }),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1, { message: "Is not set." }),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1, { message: "Is not set. This is required for server-side database operations." }),
  GOOGLE_API_KEY: z.string().min(1, { message: "Is not set. This is required for AI features." }),
  REDIS_URL: z.string().optional(),
  ENCRYPTION_KEY: z.string().length(64, { message: "Must be a 64-character hex string (32 bytes)."}).optional(),
  ENCRYPTION_IV: z.string().length(32, { message: "Must be a 32-character hex string (16 bytes)."}).optional(),
}).refine(data => {
    // If one encryption var is set, the other must be too.
    if (data.ENCRYPTION_KEY || data.ENCRYPTION_IV) {
        return !!data.ENCRYPTION_KEY && !!data.ENCRYPTION_IV;
    }
    return true;
}, {
    message: "Both ENCRYPTION_KEY and ENCRYPTION_IV must be provided if one is present.",
    path: ["ENCRYPTION_KEY", "ENCRYPTION_IV"],
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

const isProduction = process.env.NODE_ENV === 'production';

export const config = {
  app: {
    name: process.env.NEXT_PUBLIC_APP_NAME || 'InvoChat',
    url: process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000',
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
  ratelimit: {
    ai: parseIntWithDefault(process.env.RATE_LIMIT_AI, 20),
    auth: parseIntWithDefault(process.env.RATE_LIMIT_AUTH, 5),
    import: parseIntWithDefault(process.env.RATE_LIMIT_IMPORT, 10),
  },
  businessLogic: {
    deadStockDays: parseIntWithDefault(process.env.BL_DEAD_STOCK_DAYS, 90),
    fastMovingDays: parseIntWithDefault(process.env.BL_FAST_MOVING_DAYS, 30),
    predictiveStockDays: parseIntWithDefault(process.env.BL_PREDICTIVE_STOCK_DAYS, 7),
    overstockMultiplier: parseIntWithDefault(process.env.BL_OVERSTOCK_MULTIPLIER, 3),
    highValueThreshold: parseIntWithDefault(process.env.BL_HIGH_VALUE_THRESHOLD, 100000),
  },
  chat: {
    quickActions: [
      "What should I order today?",
      "What's not selling?",
      "Show me dead stock",
      "Top products this month",
    ],
  },
  ui: {
    sidebarCookieMaxAge: parseIntWithDefault(process.env.UI_SIDEBAR_COOKIE_MAX_AGE, 60 * 60 * 24 * 7), // 7 days
  },
  smb: SMB_CONFIG,
};


// A type alias for convenience
export type AppConfig = typeof config;

