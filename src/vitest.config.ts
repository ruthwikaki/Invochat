import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/tests/setup.ts'],
    // Ensure Vitest only runs unit tests
    include: ['src/tests/unit/**/*.{test,spec}.{ts,tsx}'],
    // Exclude all other test types
    exclude: [
      '**/node_modules/**',
      '**/dist/**',
      'src/tests/e2e/**',
      'src/tests/integration/**',
      'src/tests/security/**',
      'src/tests/api/**',
      'src/**/*.spec.{ts,tsx}',
    ],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
