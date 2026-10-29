import { defineConfig, devices } from '@playwright/test'

// The Secure Door board (no sign-in: it shows only non-secret data).
// Run by `make rotation-consumer-test` (c07), using ui/node_modules via a symlink.
export default defineConfig({
  testDir: '.',
  workers: 1,
  timeout: 120_000,
  reporter: 'list',
  use: { baseURL: process.env.SG_BOARD_URL, screenshot: 'only-on-failure', video: 'off' },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
    { name: 'phone', use: { ...devices['Pixel 5'], viewport: { width: 390, height: 844 } } },
  ],
})
