
/**
 * @fileoverview Centralized, environment-aware configuration for AIventory.
 */
import { config as dotenvConfig } from 'dotenv';
import { z } from 'zod';

// Force load .env variables at the earliest point.
dotenvConfig();

// More lenient validation for development
const EnvSchema = z.object({
  NEXT_PUBLIC_SITE_URL: z.string().url().optional().default('http://localhost:3000'),
  NEXT_PUBLIC_SUPABASE_URL: z.string().url({ message: "Must be a valid URL." }),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1, { message: "Is not set." }),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1, { message: "Is not set. This is required for server-side database operations." }),
  GOOGLE_API_KEY: z.string().optional(), // Make optional for initial setup
  REDIS_URL: z.string().optional(),
  ENCRYPTION_KEY: z.string().optional().default('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'),
  ENCRYPTION_IV: z.string().optional().default('0123456789abcdef0123456789abcdef'),
  HEALTH_CHECK_API_KEY: z.string().optional(),
  SHOPIFY_WEBHOOK_SECRET: z.string().optional(),
  WOOCOMMERCE_WEBHOOK_SECRET: z.string().optional(),
  RESEND_API_KEY: z.string().optional(),
  EMAIL_FROM: z.string().email().optional(),
  EMAIL_TEST_RECIPIENT: z.string().email().optional(),
});

// Export the result with better error handling
export const envValidation = EnvSchema.safeParse(process.env);

// Log validation errors in development
if (!envValidation.success && process.env.NODE_ENV === 'development') {
  console.warn('Environment validation warnings:', envValidation.error.flatten().fieldErrors);
}

// Rest of your config remains the same...
const parseIntWithDefault = (value: string | undefined, defaultValue: number): number => {
    if (value === undefined) return defaultValue;
    const parsed = parseInt(value, 10);
    return isNaN(parsed) ? defaultValue : parsed;
};

export const config = {
  app: {
    name: process.env.APP_NAME || 'AIventory',
    url: envValidation.success ? envValidation.data.NEXT_PUBLIC_SITE_URL : 'http://localhost:3000',
    environment: process.env.NODE_ENV,
  },
  ai: {
    model: 'googleai/gemini-1.5-flash',
    historyLimit: parseIntWithDefault(process.env.AI_HISTORY_LIMIT, 10),
    maxOutputTokens: parseIntWithDefault(process.env.AI_MAX_OUTPUT_TOKENS, 2048),
    timeoutMs: parseIntWithDefault(process.env.AI_TIMEOUT_MS, 30000),
  },
  database: {
    queryTimeout: parseIntWithDefault(process.env.DB_QUERY_TIMEOUT_MS, 15000),
  },
  ratelimit: {
    auth: process.env.TESTING === 'true' ? 1000 : parseIntWithDefault(process.env.RATELIMIT_AUTH, 100),
    ai: parseIntWithDefault(process.env.RATELIMIT_AI, 100),
    import: parseIntWithDefault(process.env.RATELIMIT_IMPORT, 50),
    sync: parseIntWithDefault(process.env.RATELIMIT_SYNC, 50),
    connect: parseIntWithDefault(process.env.RATELIMIT_CONNECT, 20),
  },
  import: {
    maxFileSizeMB: parseIntWithDefault(process.env.IMPORT_MAX_FILE_SIZE_MB, 10),
    batchSize: parseIntWithDefault(process.env.IMPORT_BATCH_SIZE, 500),
  },
  integrations: {
    syncDelayMs: parseIntWithDefault(process.env.INTEGRATION_SYNC_DELAY_MS, 500),
    webhookReplayWindowSeconds: parseIntWithDefault(process.env.INTEGRATION_WEBHOOK_REPLAY_SECONDS, 300),
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
        aiQuery: parseIntWithDefault(process.env.REDIS_TTL_AI_QUERY_SECONDS, 3600),
        dashboard: parseIntWithDefault(process.env.REDIS_TTL_DASHBOARD_SECONDS, 900),
        performanceMetrics: parseIntWithDefault(process.env.REDIS_TTL_PERF_METRICS_SECONDS, 86400),
    }
  }
};

export type AppConfig = typeof config;
