

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Production optimizations
  compress: true,
  poweredByHeader: false,
  webpack: (config, { dev }) => {
    // This setting can help resolve strange build issues on Windows,
    // especially when the project is in a cloud-synced directory like OneDrive.
    config.resolve.symlinks = false;
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
  async headers() {
    // SECURITY FIX (#99): Tightened Content Security Policy.
    // Removed 'unsafe-inline' and 'unsafe-eval' to prevent XSS attacks.
    // Note: 'unsafe-inline' for styles is temporarily kept for ShadCN compatibility,
    // but a stricter nonce-based approach would be better long-term.
    const cspHeader = `
      default-src 'self';
      script-src 'self';
      style-src 'self' 'unsafe-inline';
      img-src 'self' data: https://placehold.co;
      font-src 'self';
      connect-src 'self' https://*.supabase.co wss://*.supabase.co https://generativelanguage.googleapis.com;
      frame-ancestors 'none';
      base-uri 'self';
      form-action 'self';
      object-src 'none';
    `.replace(/\s{2,}/g, ' ').trim();

    return [
      {
        // Apply these headers to all routes in your application.
        source: '/:path*',
        headers: [
          {
            key: 'Content-Security-Policy',
            value: cspHeader,
          },
          {
            key: 'X-Content-Type-Options',
            value: 'nosniff',
          },
          {
            key: 'X-Frame-Options',
            value: 'SAMEORIGIN',
          },
          {
            key: 'Strict-Transport-Security',
            value: 'max-age=63072000; includeSubDomains; preload',
          },
          {
            key: 'Referrer-Policy',
            value: 'origin-when-cross-origin',
          },
          {
            key: 'Permissions-Policy',
            value: "camera=(), microphone=(), geolocation=()",
          }
        ],
      },
    ];
  },
};


module.exports = nextConfig;
