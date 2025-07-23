import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tsconfigPaths from 'vite-tsconfig-paths'
import path from 'path';

// This configuration is now simplified to let Vitest handle environment variables automatically.
// Vitest will automatically load `.env.test` when `NODE_ENV` is 'test'.
export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/tests/setup.ts'],
    // By default, process.env.NODE_ENV is 'test' when running vitest.
    // This will cause it to automatically look for and load `.env.test`
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
  resolve: {
      alias: {
          '@': path.resolve(__dirname, './src')
      }
  }
})
