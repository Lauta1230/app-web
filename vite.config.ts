import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  server: { host: '0.0.0.0', allowedHosts: true },
  preview: { host: '0.0.0.0', allowedHosts: true },
  test: {
    environment: 'jsdom',
    globals: true,
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined
          if (id.includes('react') || id.includes('scheduler')) return 'react-vendor'
          if (id.includes('@supabase')) return 'supabase-vendor'
          if (id.includes('lucide-react')) return 'icons-vendor'
          if (id.includes('katex') || id.includes('marked')) return 'katex-vendor'
          return 'vendor'
        }
      }
    }
  },
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg', 'pwa-192.png', 'pwa-512.png'],
      manifest: {
        name: 'Compañero de Estudio',
        short_name: 'Estudio',
        description: 'Tu compañero de estudio con IA.',
        theme_color: '#121620',
        background_color: '#121620',
        display: 'standalone',
        scope: '/',
        start_url: '/app',
        lang: 'es-AR',
        icons: [
          { src: 'pwa-192.png', sizes: '192x192', type: 'image/png', purpose: 'any maskable' },
          { src: 'pwa-512.png', sizes: '512x512', type: 'image/png', purpose: 'any maskable' }
        ]
      },
      workbox: {
        navigateFallback: '/index.html',
        globPatterns: ['**/*.{js,css,html,svg,png,ico}'],
        runtimeCaching: [{
          urlPattern: /^https:\/\/.*\.supabase\.co\/storage\/v1\/object\/public\/.*$/i,
          handler: 'CacheFirst',
          options: { cacheName: 'study-assets', expiration: { maxEntries: 30, maxAgeSeconds: 60 * 60 * 24 * 7 } }
        }]
      }
    })
  ]
})
