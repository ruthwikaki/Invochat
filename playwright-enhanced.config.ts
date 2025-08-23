import { defineConfig, devices } from '@playwright/test';
import path from 'path';

// Extend base configuration with enhanced testing capabilities
export default defineConfig({
  // Test directory
  testDir: './src/tests',
  
  // Include enhanced test suites
  testMatch: [
    '**/e2e/**/*.spec.ts',
    '**/accessibility/**/*.spec.ts',
    '**/performance/**/*.spec.ts',
    '**/security/**/*.spec.ts',
    '**/load/**/*.spec.ts'
  ],

  // Global timeout for each test
  timeout: 90 * 1000,

  // Global timeout for entire test suite
  globalTimeout: 60 * 60 * 1000, // 1 hour

  // Expect timeout for assertions
  expect: { timeout: 10000 },

  // Fail the build on CI if you accidentally left test.only in the source code
  forbidOnly: !!process.env.CI,

  // Retry on CI only
  retries: process.env.CI ? 2 : 1,

  // Opt out of parallel tests on CI
  workers: process.env.CI ? 1 : 4,

  // Shared settings for all tests
  use: {
    // Base URL for tests
    baseURL: process.env.BASE_URL || 'http://localhost:3000',

    // Browser context options
    viewport: { width: 1280, height: 720 },
    
    // Collect trace on failure
    trace: 'retain-on-failure',
    
    // Take screenshot on failure
    screenshot: 'only-on-failure',
    
    // Record video on failure
    video: 'retain-on-failure',

    // Ignore HTTPS errors
    ignoreHTTPSErrors: true,

    // Custom test data
    extraHTTPHeaders: {
      'Accept-Language': 'en-US,en;q=0.9',
    },

    // Performance monitoring
    actionTimeout: 15000,
    navigationTimeout: 30000,
  },

  // Enhanced test projects for comprehensive coverage
  projects: [
    // Desktop browsers
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },

    // Mobile devices for responsive testing
    {
      name: 'Mobile Chrome',
      use: { ...devices['Pixel 5'] },
    },
    {
      name: 'Mobile Safari',
      use: { ...devices['iPhone 12'] },
    },

    // Tablet devices
    {
      name: 'iPad',
      use: { ...devices['iPad Pro'] },
    },

    // Accessibility testing with screen readers
    {
      name: 'chromium-a11y',
      use: { 
        ...devices['Desktop Chrome'],
        // Enable accessibility features
        launchOptions: {
          args: ['--force-prefers-reduced-motion', '--enable-features=WebContentsForceDarkMode']
        }
      },
      testMatch: '**/accessibility/**/*.spec.ts'
    },

    // Performance testing
    {
      name: 'performance',
      use: { 
        ...devices['Desktop Chrome'],
        // Enable performance monitoring
        launchOptions: {
          args: ['--enable-automation', '--disable-web-security']
        }
      },
      testMatch: '**/performance/**/*.spec.ts'
    },

    // Security testing
    {
      name: 'security',
      use: { 
        ...devices['Desktop Chrome'],
        // Security-focused configuration
        ignoreHTTPSErrors: false,
        extraHTTPHeaders: {
          'X-Security-Test': 'true'
        }
      },
      testMatch: '**/security/**/*.spec.ts'
    },

    // Load testing
    {
      name: 'load-testing',
      use: { 
        ...devices['Desktop Chrome'],
        // Load testing configuration
        launchOptions: {
          args: ['--disable-background-timer-throttling', '--disable-renderer-backgrounding']
        }
      },
      testMatch: '**/load/**/*.spec.ts'
    }
  ],

  // Test result reporters
  reporter: [
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
    ['json', { outputFile: 'playwright-report/results.json' }],
    ['junit', { outputFile: 'playwright-report/results.xml' }],
    ['list'],
    // Custom reporter for detailed metrics
    [path.resolve(__dirname, 'src/tests/utils/custom-reporter.ts')]
  ],

  // Output directory for test artifacts
  outputDir: 'test-results/',

  // Global setup and teardown
  globalSetup: path.resolve(__dirname, 'src/tests/global-setup.ts'),
  globalTeardown: path.resolve(__dirname, 'src/tests/global-teardown.ts'),

  // Web server for testing
  webServer: {
    command: 'npm run dev',
    port: 3000,
    reuseExistingServer: !process.env.CI,
    timeout: 120 * 1000,
  },

  // Enhanced test metadata
  metadata: {
    testType: 'enhanced-e2e',
    coverage: '95-percent-target',
    performance: 'enabled',
    accessibility: 'wcag-2.1-aa',
    security: 'owasp-top-10'
  }
});
