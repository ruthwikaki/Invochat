/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Remove all complex configurations temporarily
  experimental: {
    serverComponentsExternalPackages: [
      '@supabase/supabase-js',
    ],
  },
};

module.exports = nextConfig;
