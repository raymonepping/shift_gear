import { defineConfig, devices } from '@playwright/test'

// Runs against the deployed console through scripts/ui-test.sh.
// Browser contexts verify TLS using the host’s trusted certificate authorities.
export default defineConfig({
  testDir: 'tests',
  workers: 1, // provider logout deliberately invalidates all sessions of that subject
  timeout: 90_000,
  reporter: process.env.CI ? 'github' : 'list',
  fullyParallel: false, // tests share a signed-in session; serialise within project
  globalSetup: './tests/global-setup.ts',

  use: {
    baseURL: process.env.SG_UI_URL || 'http://127.0.0.1:3400',
    screenshot: 'only-on-failure',
    video: 'off',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'mobile-chrome',
      use: { ...devices['Pixel 5'] },
    },
  ],

  // `@screens` tests capture screenshots only — run explicitly with make ui-screens.
  // `@failover` tests need a live cluster — run explicitly with make ui-test-failover.
})
