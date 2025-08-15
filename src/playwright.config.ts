
import { defineConfig, devices } from '@playwright/test';
import dotenv from 'dotenv';
import path from 'path';

// Load test environment variables from the root .env file
dotenv.config({ path: path.resolve(__dirname, '../.env') });


/**
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  testDir: './src/tests',
  // Only include files with .spec.ts for Playwright E2E tests
  testMatch: '**/*.spec.ts',
  // Exclude unit tests from Playwright runs
  testIgnore: '**/unit/**',
  /* Run tests in files in parallel */
  fullyParallel: true,
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  /* Retry on CI only */
  retries: process.env.CI ? 2 : 0,
  /* Opt out of parallel tests on CI. */
  workers: process.env.CI ? 1 : undefined,
  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  reporter: 'html',
  // Increase the default timeout to 60 seconds to handle slow data loads
  timeout: 60 * 1000,
  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL: 'http://localhost:3000',
    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: 'on-first-retry',
  },

  /* Configure projects for major browsers */
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  /* Run your local dev server before starting the tests */
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120000, // Increased timeout for server start
    stdout: 'pipe',
    stderr: 'pipe',
    env: {
        // Pass all necessary env vars to the test server
        NEXT_PUBLIC_SITE_URL: 'http://localhost:3000',
        NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
        NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
        SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
        GOOGLE_API_KEY: process.env.GOOGLE_API_KEY,
        REDIS_URL: process.env.REDIS_URL,
        ENCRYPTION_KEY: process.env.ENCRYPTION_KEY,
        ENCRYPTION_IV: process.env.ENCRYPTION_IV,
        SHOPIFY_WEBHOOK_SECRET: process.env.SHOPIFY_WEBHOOK_SECRET || 'test_secret_for_ci',
        WOOCOMMERCE_WEBHOOK_SECRET: process.env.WOOCOMMERCE_WEBHOOK_SECRET || 'test_secret_for_ci',
        HEALTH_CHECK_API_KEY: process.env.HEALTH_CHECK_API_KEY || 'test_health_key',
        TESTING_API_KEY: process.env.TESTING_API_KEY || 'test_api_key_for_ci',
        // This is important: tells the app to use mocked AI responses for tests
        // to avoid actual API calls to Google, making tests faster and more reliable.
        MOCK_AI: 'true',
    }
  },
});
