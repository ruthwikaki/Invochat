/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  webpack: (config, { dev }) => {
    if (dev) {
      // Prevent webpack from following symlinks, which might be causing issues on Windows/OneDrive
      config.resolve.symlinks = false; 
    }
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
