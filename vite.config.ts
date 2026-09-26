import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// The site uses real paths (/teams/alabama/), so assets need an absolute base. Production serves from
// https://whcavender14.github.io/cfb-power-index/; override with CFPI_BASE=/ for a root-hosted build.
// Every route is prerendered as its own index.html after the build (scripts/prerender_routes.mjs).
export default defineConfig(({ command }) => ({
  plugins: [react(), tailwindcss()],
  base: process.env.CFPI_BASE ?? (command === 'build' ? '/cfb-power-index/' : '/'),
}))
