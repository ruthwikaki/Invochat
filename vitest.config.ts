import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';
import path from 'path';

export default defineConfig({
  // @ts-ignore - plugin type compatibility issue between vite and vitest
  plugins: [react(), tsconfigPaths()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/tests/setup.ts'],
    // Run only unit tests with Vitest
    include: ['src/tests/unit/**/*.test.{ts,tsx}'],
    // Exclude all other tests (like Playwright .spec files)
    exclude: [
      'node_modules/',
      'src/tests/**/*.spec.ts',
      'src/tests/e2e/**',
      'src/tests/api/**'
    ],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html', 'lcov'],
      reportsDirectory: './coverage',
      exclude: [
        'node_modules/',
        'src/tests/',
        '**/*.d.ts',
        '**/*.config.{js,ts}',
        '**/dist/**',
        '.next/**',
        'coverage/**',
        'playwright-report/**',
        'test-results/**',
      ],
      // Include all source files for coverage analysis
      include: [
        'src/**/*.{ts,tsx}',
        '!src/tests/**',
        '!src/**/*.spec.{ts,tsx}',
        '!src/**/*.test.{ts,tsx}',
        '!src/**/*.d.ts'
      ],
      all: true
    },
    // Increase timeout for more complex tests
    testTimeout: 30000,
    // Enable parallel execution
    maxConcurrency: 4,
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
});
