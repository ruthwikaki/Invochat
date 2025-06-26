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
    serverComponentsExternalPackages: ['@opentelemetry/instrumentation'],
  },
};

module.exports = nextConfig;
