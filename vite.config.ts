import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// Relative assets work at both username.github.io and /repository/ URLs.
export default defineConfig({ plugins: [react(), tailwindcss()], base: './' })
