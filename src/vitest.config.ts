import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tsconfigPaths from 'vite-tsconfig-paths'

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/tests/setup.ts'],
    // Run only unit tests with Vitest
    include: ['src/tests/unit/**/*.test.{ts,tsx}'],
    // Exclude all other tests (like Playwright .spec files)
    exclude: [
      'node_modules/**',
      'src/tests/**/*.{spec}.{ts,tsx}',
      'src/tests/e2e/**'
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
