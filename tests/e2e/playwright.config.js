import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  testMatch: '**/*.spec.js',
  timeout: 30_000,
  retries: 0,
  use: {
    baseURL: 'http://localhost:5199',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'npm run dev -- --port 5199 --strictPort',
    cwd: '../../apps/qr_web',
    url: 'http://localhost:5199',
    reuseExistingServer: false,
    timeout: 30_000,
    env: {
      // Nilai dummy: semua RPC dimocking lewat page.route, tidak ada jaringan.
      VITE_SUPABASE_URL: 'https://e2e-mock.supabase.co',
      VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_e2e-mock',
    },
  },
});
