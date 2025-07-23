
import { defineConfig } from 'vitest/config'
import path from 'path'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  test: {
    // Only include unit tests for Vitest
    include: [
      'src/tests/unit/**/*.test.ts',
      'src/tests/unit/**/*.test.tsx'
    ],
    // Exclude Playwright tests and other non-unit tests
    exclude: [
      'src/tests/e2e/**/*',
      'src/tests/api/**/*',
      'src/tests/integration/**/*',
      'src/tests/performance/**/*',
      'src/tests/security/**/*',
      'src/tests/*.spec.ts',
      'node_modules/**/*'
    ],
    environment: 'jsdom',
    setupFiles: ['src/tests/setup.ts'],
    globals: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        'src/tests/',
        '**/*.d.ts',
        '**/*.config.{js,ts}',
        '**/dist/**'
      ]
    }
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './')
    }
  },
})
