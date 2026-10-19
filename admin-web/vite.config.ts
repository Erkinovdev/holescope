import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

// API бэкенда: в разработке проксируем /api на Docker-бэкенд (порт из backend/.env WEB_PORT)
const API = process.env.VITE_API_PROXY ?? 'http://127.0.0.1:8010'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: { port: 5180, proxy: { '/api': API, '/media': API } },
  build: {
    chunkSizeWarningLimit: 1500,
    rollupOptions: { output: { manualChunks: (id: string) => (/node_modules[\/]maplibre-gl/.test(id) ? 'maplibre' : undefined) } },
  },
  test: { environment: 'jsdom', globals: true, setupFiles: ['./src/test/setup.ts'], css: false },
})
