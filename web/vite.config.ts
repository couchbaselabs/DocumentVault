import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { componentTagger } from "lovable-tagger";

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  server: {
    host: "::",
    port: 8080,
    proxy: {
      '/sync-gateway': {
        target: 'https://gal7pf8dclbqfk.apps.cloud.couchbase.com:4984',
        changeOrigin: true,
        secure: false, // Bypass SSL certificate verification for local proxying
        ws: true,
        rewrite: (path) => path.replace(/^\/sync-gateway/, ''),
        headers: {
          Host: 'gal7pf8dclbqfk.apps.cloud.couchbase.com:4984',
        },
        configure: (proxy, _options) => {
          proxy.on('error', (err, _req, _res) => {
            console.log('🔴 Vite Proxy Error:', err.message);
          });
          proxy.on('proxyReq', (proxyReq, req, _res) => {
            // Force headers for Capella App Services to prevent 400 Bad Request
            proxyReq.setHeader('Host', 'gal7pf8dclbqfk.apps.cloud.couchbase.com:4984');
            proxyReq.setHeader('Origin', 'https://gal7pf8dclbqfk.apps.cloud.couchbase.com:4984');

            // Restructure/restore request body if it was parsed by Vite middleware
            // to prevent empty payload (EOF) rejections from Sync Gateway
            if ((req as any).body) {
              const bodyData = JSON.stringify((req as any).body);
              proxyReq.setHeader('Content-Type', 'application/json');
              proxyReq.setHeader('Content-Length', Buffer.byteLength(bodyData));
              proxyReq.write(bodyData);
            }
          });
          proxy.on('proxyReqWs', (proxyReq, req, _socket, _options, _head) => {
            console.log('📡 Proxying WebSocket to Capella:', req.url);
            proxyReq.setHeader('Host', 'gal7pf8dclbqfk.apps.cloud.couchbase.com:4984');
            proxyReq.setHeader('Origin', 'https://gal7pf8dclbqfk.apps.cloud.couchbase.com:4984');
            proxyReq.setHeader('sec-websocket-extensions', '');
          });
        }
      }
    }
  },
  plugins: [
    react(),
    mode === 'development' &&
    componentTagger(),
  ].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src")
    },
  },
}));