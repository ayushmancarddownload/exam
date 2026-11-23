import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

// SITE and BASE are set by the GitHub Actions workflow (see .github/workflows/deploy.yml).
export default defineConfig({
  output: 'static', // required for GitHub Pages
  site: process.env.SITE || 'http://localhost:4321',
  base: process.env.BASE || '/',
  trailingSlash: 'always',
  vite: { plugins: [tailwindcss()] },
});
