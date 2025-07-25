
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
    // This is required to fix critical dependency warnings/errors with server-side packages.
    // Adding these prevents webpack errors and allows Genkit, Supabase, and Redis
    // to function correctly in server actions and server components.
    serverComponentsExternalPackages: [
      '@opentelemetry/instrumentation',
      'handlebars',
      '@supabase/supabase-js',
      '@supabase/realtime-js',
      'ioredis',
    ],
  },
});

// The Sentry webpack plugin gets loaded here.
const { withSentryConfig } = require("@sentry/nextjs");

module.exports = withSentryConfig(
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
