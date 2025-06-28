/**
 * @fileoverview Centralized, environment-aware configuration for InvoChat.
 *
 * This file consolidates all external configuration, pulling from environment
 * variables with sensible defaults. This is crucial for security and for
 * operating the application across different environments (dev, staging, prod).
 */
import { z } from 'zod';

// Helper to parse numbers from env vars
const parseIntWithDefault = (value: string | undefined, defaultValue: number): number => {
    if (value === undefined) return defaultValue;
    const parsed = parseInt(value, 10);
    return isNaN(parsed) ? defaultValue : parsed;
};

export const config = {
  app: {
    name: process.env.NEXT_PUBLIC_APP_NAME || 'InvoChat',
    url: process.env.NEXT_PUBLIC_SITE_URL!,
    environment: process.env.NODE_ENV || 'development',
  },
  ai: {
    model: process.env.AI_MODEL || 'googleai/gemini-1.5-flash',
    maxRetries: parseIntWithDefault(process.env.AI_MAX_RETRIES, 2),
    timeout: parseIntWithDefault(process.env.AI_TIMEOUT, 30000),
    historyLimit: parseIntWithDefault(process.env.AI_HISTORY_LIMIT, 10),
  },
  database: {
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
};

// Runtime validation schema to ensure critical env vars are set
const ConfigSchema = z.object({
    app: z.object({
        name: z.string(),
        url: z.string().min(1, "NEXT_PUBLIC_SITE_URL is not set.").url("NEXT_PUBLIC_SITE_URL must be a valid URL."),
        environment: z.string(),
    }),
    ai: z.object({
        model: z.string(),
        maxRetries: z.number().int().min(0),
        timeout: z.number().int().min(0),
        historyLimit: z.number().int().min(0),
    }),
});

// Validate the config on startup. This will throw an error during the build if critical env vars are missing.
// This satisfies the "Configuration Validation on app startup" requirement.
try {
    ConfigSchema.parse(config);
} catch (e: any) {
    console.error("❌ Invalid application configuration:", e.errors);
    // In a server environment, we should exit gracefully.
    // In a Next.js build process, this will cause the build to fail, which is what we want.
    if (typeof process.exit === 'function') {
        process.exit(1);
    }
    // Fallback for environments where process.exit is not available
    throw new Error("Invalid application configuration. Check server logs for details.");
}

// A type alias for convenience
export type AppConfig = typeof config;
