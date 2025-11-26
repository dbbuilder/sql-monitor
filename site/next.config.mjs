/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  images: {
    domains: ['raw.githubusercontent.com'],
  },
  env: {
    NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL || 'https://sqlmonitor.servicevision.net',
  },
};

export default nextConfig;
