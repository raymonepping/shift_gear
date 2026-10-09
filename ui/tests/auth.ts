// tests/auth.ts — sign-in helpers for Shift Gear Playwright specs.
// Uses the real Keycloak login page — nothing stubbed.
import type { Browser, Page } from '@playwright/test'
import { passwordOf, stateFile, type User } from './users'

export const BASE = process.env.SG_UI_URL ?? 'http://127.0.0.1:3400'

export async function signIn(page: Page, user: User) {
  await page.goto(`${BASE}/signin`)
  await page.getByTestId('sign-in').click()
  // Redirected to Keycloak
  await page.waitForURL(/\/realms\//)
  await page.locator('#username').fill(user)
  await page.locator('#password').fill(passwordOf(user))
  await page.locator('#kc-login').click()
  // Wait for redirect back to Shift Gear (not /signin or /auth/*)
  await page.waitForURL(u => u.href.startsWith(BASE) && !/^\/(signin|auth)/.test(u.pathname), { timeout: 30_000 })
}

/** A signed-in page for `user`, restored from global-setup's storageState. */
export async function pageAs(browser: Browser, user: User, opts: Parameters<Browser['newContext']>[0] = {}) {
  const context = await browser.newContext({ storageState: stateFile(user), ignoreHTTPSErrors: true, ...opts })
  const page = await context.newPage()
  return { context, page }
}
