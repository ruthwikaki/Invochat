/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  webpack: (config, { dev }) => {
    if (dev) {
      config.cache = false;
      config.watchOptions = {
        poll: 1000, // Check for changes every second
        aggregateTimeout: 300, // Delay before rebuilding
      };
      // Prevent webpack from following symlinks, which might be causing issues on Windows/OneDrive
      config.resolve.symlinks = false; 
    }
    return config;
  },
};

module.exports = nextConfig;
