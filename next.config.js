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
  compress: true,
  poweredByHeader: false,

  // Add error handling for development
  onDemandEntries: {
    maxInactiveAge: 25 * 1000,
    pagesBufferLength: 2
  },

  webpack: (config, { isServer, webpack, dev }) => {
    config.resolve.symlinks = false

    if (!isServer) {
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

    // Better error handling in development
    if (dev) {
      config.watchOptions = {
        poll: 1000,
        aggregateTimeout: 300
      }
    }

    config.externals.push({
      '@opentelemetry/instrumentation': 'commonjs @opentelemetry/instrumentation'
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
  },

  experimental: {
    serverComponentsExternalPackages: [
      '@opentelemetry/instrumentation',
      '@opentelemetry/exporter-jaeger',
      'handlebars',
      '@supabase/supabase-js',
      '@supabase/realtime-js',
      'ioredis'
    ]
  }
})

// Only add Sentry in production or if explicitly configured
let finalConfig = nextConfig

try {
  if (process.env.SENTRY_ORG && process.env.SENTRY_PROJECT) {
    const { withSentryConfig } = require('@sentry/nextjs')
    finalConfig = withSentryConfig(
      nextConfig,
      {
        silent: true,
        org: process.env.SENTRY_ORG,
        project: process.env.SENTRY_PROJECT
      },
      {
        hideSourceMaps: true,
        disableLogger: true,
        automaticVercelMonitors: true
      }
    )
  }
} catch (error) {
  console.warn('Sentry configuration skipped:', error.message)
}

module.exports = finalConfig
