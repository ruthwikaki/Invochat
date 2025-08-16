
import { defineConfig, devices } from '@playwright/test';
import dotenv from 'dotenv';
import path from 'path';

// Load test environment variables
dotenv.config({ path: path.resolve(__dirname, '.env.test') });

export default defineConfig({
  testDir: './src/tests',
  testMatch: '**/*.spec.ts',
  testIgnore: '**/unit/**',
  /* Run tests in files in parallel */
  fullyParallel: true,
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  /* Retry on CI only */
  retries: process.env.CI ? 2 : 0,
  /* Opt out of parallel tests on CI. */
  workers: process.env.CI ? 1 : 1, // Reduced from 2 to 1 to avoid rate limiting
  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  reporter: 'html',
  timeout: 90 * 1000, // Increased from 60s to 90s
  
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    actionTimeout: 30000, // Increased from 15s to 30s
    navigationTimeout: 60000, // Increased from 30s to 60s
  },

  projects: [
    {
      name: 'setup',
      testMatch: /global-setup\.ts/,
    },
    {
      name: 'auth-setup',
      testMatch: /auth-setup\.ts/,
      dependencies: ['setup'],
    },
    {
      name: 'auth-tests',
      testMatch: /(auth|login|signup).*\.spec\.ts/,
      use: { 
        ...devices['Desktop Chrome'],
        // No shared auth state for auth tests
      },
      dependencies: ['setup'],
    },
    {
      name: 'chromium',
      testMatch: ['**/*.spec.ts', '!**/auth*.spec.ts', '!**/login*.spec.ts', '!**/signup*.spec.ts'],
      use: { 
        ...devices['Desktop Chrome'],
        // Use shared authentication state to avoid repeated logins
        storageState: './playwright/.auth/user.json',
      },
      dependencies: ['auth-setup'],
    },
  ],

  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120 * 1000, // Increased timeout for server start
    stdout: 'pipe',
    stderr: 'pipe',
  },
});
