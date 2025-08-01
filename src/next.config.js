// @ts-check

/**
 * @template {import('next').NextConfig} T
 * @param {T} config
 * @returns {T}
 */
function defineNextConfig(config) {
  return config;
}


/** @type {import('next').NextConfig} */
const nextConfig = defineNextConfig({
  reactStrictMode: true,
  // Production optimizations
  compress: true,
  poweredByHeader: false,
  webpack: (config, { isServer, webpack }) => {
    // This setting can help resolve strange build issues on Windows,
    // especially when the project is in a cloud-synced directory like OneDrive.
    config.resolve.symlinks = false;

    if (!isServer) {
        config.plugins.push(
            new webpack.ContextReplacementPlugin(
                /@opentelemetry\/instrumentation/,
                (data) => {
                    for (const dependency of data.dependencies) {
                        if (dependency.request === './platform/node') {
                            dependency.request = './platform/browser';
                        }
                    }
                    return data;
                }
            )
        )
    }

    // This is the correct way to suppress the specific, known warnings from Sentry/Supabase.
    // It prevents the build log from being cluttered with non-actionable "Critical dependency" messages.
    config.externals.push({
        '@opentelemetry/instrumentation': 'commonjs @opentelemetry/instrumentation',
    });

    config.module.rules.push({
      test: /realtime-js/,
      loader: 'string-replace-loader',
      options: {
        search: 'Ably from "ably"',
        replace: 'Ably from "ably/browser/core"',
      }
    });

    return config;
  },
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'placehold.co',
      },
    ],
  },
  experimental: {
    appDir: true,
    serverComponentsExternalPackages: [
      '@opentelemetry/instrumentation',
      '@opentelemetry/exporter-jaeger',
      'handlebars',
      '@supabase/supabase-js',
      '@supabase/realtime-js',
      'ioredis',
    ],
  },
});

// Initialize a variable to hold the final config.
let finalConfig = nextConfig;

// Only wrap with Sentry if the required environment variables are present.
// This prevents the application from crashing at startup if Sentry is not configured.
if (process.env.SENTRY_ORG && process.env.SENTRY_PROJECT && process.env.SENTRY_DSN) {
  try {
    const { withSentryConfig } = require("@sentry/nextjs");
    finalConfig = withSentryConfig(
      nextConfig,
      {
        // For all available options, see:
        // https://github.com/getsentry/sentry-webpack-plugin#options

        // Suppresses source map uploading logs during build
        silent: true,
        org: process.env.SENTRY_ORG,
        project: process.env.SENTRY_PROJECT,
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
        automaticVercelMonitors: true,
      }
    );
  } catch (e) {
      console.warn("Sentry configuration failed to load. Skipping Sentry.", e);
  }
} else {
    console.warn("Sentry environment variables (SENTRY_ORG, SENTRY_PROJECT, SENTRY_DSN) not found. Skipping Sentry configuration.");
}


module.exports = finalConfig;
