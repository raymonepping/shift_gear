import { defineConfig, devices } from '@playwright/test'

// Runs against an already-running Shift Gear UI (make ui-dev or make ui-start).
// TLS is verified elsewhere; tests focus on UI behaviour and a11y.
export default defineConfig({
  testDir: 'tests',
  timeout: 90_000,
  reporter: process.env.CI ? 'github' : 'list',
  fullyParallel: false, // tests share a signed-in session; serialise within project
  globalSetup: './tests/global-setup.ts',

  use: {
    baseURL: process.env.SG_UI_URL || 'http://127.0.0.1:3400',
    ignoreHTTPSErrors: true,
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
