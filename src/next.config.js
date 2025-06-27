/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
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
    // This is required to fix critical warnings with server-side dependencies.
    // Adding 'handlebars' and '@supabase/supabase-js' prevents webpack errors
    // and allows Genkit and Supabase to function correctly in server actions.
    serverComponentsExternalPackages: [
      '@opentelemetry/instrumentation',
      'handlebars',
      '@supabase/supabase-js',
    ],
  },
};

module.exports = nextConfig;
