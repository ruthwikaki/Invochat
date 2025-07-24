import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

// This configuration is now simplified.
// Vitest will automatically load `.env.test` when `NODE_ENV` is 'test'
// and handle tsconfig paths without an extra plugin.
export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/tests/setup.ts'],
    include: ['src/tests/unit/**/*.test.{ts,tsx}'],
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
