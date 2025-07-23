import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tsconfigPaths from 'vite-tsconfig-paths'
import { loadEnv } from 'vite'
import path from 'path';

export default defineConfig(({ mode }) => {
  // Load env file based on the mode
  const env = loadEnv(mode, process.cwd(), '')

  return {
    plugins: [react(), tsconfigPaths()],
    test: {
      globals: true,
      environment: 'jsdom',
      setupFiles: ['./src/tests/setup.ts'],
      // Pass the loaded environment variables to the test environment
      env,
      // Run only unit tests with Vitest
      include: ['src/tests/unit/**/*.{test,tsx}'],
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
    resolve: {
        alias: {
            '@': path.resolve(__dirname, './src')
        }
    }
  }
})
