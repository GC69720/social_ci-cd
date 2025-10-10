/** @type {import('next').NextConfig} */
const isDev = process.env.NODE_ENV !== "production";

const cspDev = [
  "default-src 'self'",
  "img-src 'self' data: blob:",
  "font-src 'self' data:",
  "connect-src 'self' http: https: ws: wss:",
  "style-src 'self' 'unsafe-inline'",
  "script-src 'self' 'unsafe-inline' 'unsafe-eval'"
].join("; ");

const cspProd = [
  "default-src 'self'",
  "img-src 'self' data:",
  "font-src 'self' data:",
  "connect-src 'self'",
  "style-src 'self'",
  "script-src 'self'"
].join("; ");

const securityHeaders = [
  { key: "Content-Security-Policy", value: isDev ? cspDev : cspProd },
  { key: "Referrer-Policy", value: "no-referrer" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Permissions-Policy", value: "geolocation=(), microphone=(), camera=()" }
];

const nextConfig = {
  reactStrictMode: true,
  async headers() {
    return [
      { source: "/:path*", headers: securityHeaders }
    ];
  }
};
export default nextConfig;
