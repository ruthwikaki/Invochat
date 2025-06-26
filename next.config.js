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
    // This is required to fix a critical warning with server-side Genkit dependencies.
    // Adding 'handlebars' prevents a webpack error and allows Genkit's context
    // (including the companyId for tools) to propagate correctly in server actions.
    serverComponentsExternalPackages: ['@opentelemetry/instrumentation', 'handlebars'],
  },
};

module.exports = nextConfig;
