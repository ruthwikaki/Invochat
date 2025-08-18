// @ts-check

/**
 * @template {import('next').NextConfig} T
 * @param {T} config
 * @returns {T}
 */
function defineNextConfig (config) {
  return config
}

/** @type {import('next').NextConfig} */
const nextConfig = defineNextConfig({
  reactStrictMode: true,
  // Production optimizations
  compress: true,
  poweredByHeader: false,
  env: {
    GOOGLE_API_KEY: process.env.GOOGLE_API_KEY
  },
  webpack: (config, { isServer, webpack }) => {
    config.resolve.symlinks = false

    if (!isServer) {
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        net: false,
        tls: false
      }

      config.plugins.push(
        new webpack.ContextReplacementPlugin(
          /@opentelemetry\/instrumentation/,
          (data) => {
            for (const dependency of data.dependencies) {
              if (dependency.request === './platform/node') {
                dependency.request = './platform/browser'
              }
            }
            return data
          }
        )
      )
    }

    config.externals = config.externals || []
    config.externals.push({
      '@opentelemetry/instrumentation': 'commonjs2 @opentelemetry/instrumentation',
      'require-in-the-middle': 'commonjs2 require-in-the-middle'
    })

    config.module.rules.push({
      test: /realtime-js/,
      loader: 'string-replace-loader',
      options: {
        search: 'Ably from "ably"',
        replace: 'Ably from "ably/browser/core"'
      }
    })

    return config
  },
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'placehold.co'
      }
    ]
  }
})

// Initialize a variable to hold the final config.
let finalConfig = nextConfig

// Only wrap with Sentry if the required environment variables are present.
// This prevents the application from crashing at startup if Sentry is not configured.
if (process.env.SENTRY_ORG && process.env.SENTRY_PROJECT && process.env.SENTRY_DSN) {
  try {
    const { withSentryConfig } = require('@sentry/nextjs')
    finalConfig = withSentryConfig(
      nextConfig,
      {
        // For all available options, see:
        // https://github.com/getsentry/sentry-webpack-plugin#options

        // Suppresses source map uploading logs during build
        silent: true,
        org: process.env.SENTRY_ORG,
        project: process.env.SENTRY_PROJECT
      },
      {
        // For all available options, see:
        // https://docs.sentry.io/platforms/javascript/guides/nextjs/manual-setup/

        // Hides source maps from generated client bundles
        hideSourceMaps: true,

        // Automatically tree-shake Sentry logger statements to reduce bundle size
        disableLogger: true,

        // Enables automatic instrumentation of Vercel Cron Monitors.
        // See the following for more information:
        // https://docs.sentry.io/platforms/javascript/guides/nextjs/configuration/integrations/vercel-cron-monitors/
        automaticVercelMonitors: true
      }
    )
  } catch (e) {
    console.warn('Sentry configuration failed to load. Skipping Sentry.', e)
  }
} else {
  console.warn('Sentry environment variables (SENTRY_ORG, SENTRY_PROJECT, SENTRY_DSN) not found. Skipping Sentry configuration.')
}

module.exports = finalConfig
