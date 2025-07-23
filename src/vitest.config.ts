
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tsconfigPaths from 'vitest-tsconfig-paths'

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    // Only include files with .test.ts or .test.tsx for Vitest
    include: ['src/tests/unit/**/*.test.{ts,tsx}'],
    // Exclude all other tests, especially Playwright spec files
    exclude: [
      'src/tests/*.spec.ts',
      'src/tests/e2e/**/*.spec.ts',
      'src/tests/api/**/*.spec.ts',
      'src/tests/integration/**/*.spec.ts',
      'src/tests/performance/**/*.spec.ts',
      'src/tests/security/**/*.spec.ts',
      'node_modules/**/*',
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
        '**/dist/**',
      ],
    },
  },
})
