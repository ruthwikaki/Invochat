
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tsconfigPaths from 'vitest-tsconfig-paths'

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/tests/setup.ts'],
    // Only include files in the unit directory for Vitest
    include: ['src/tests/unit/**/*.test.{ts,tsx}'],
    // Exclude all other tests
    exclude: [
      'src/tests/*.spec.ts',
      'src/tests/e2e/**/*.spec.ts',
      'src/tests/api/**/*.spec.ts',
      'src/tests/integration/**/*.spec.ts',
      'src/tests/performance/**/*.spec.ts',
      'src/tests/security/**/*.spec.ts',
      'node_modules/**/*',
    ],
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
