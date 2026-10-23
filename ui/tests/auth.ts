// tests/auth.ts — sign-in helpers for Shift Gear Playwright specs.
// Uses the real Keycloak login page — nothing stubbed.
import { chmodSync } from 'node:fs'
import type { Browser, Page } from '@playwright/test'
import { passwordOf, stateFile, type User } from './users'

export const BASE = process.env.SG_UI_URL ?? 'http://127.0.0.1:3400'

export async function signIn(page: Page, user: User) {
  await page.goto(`${BASE}/signin`)
  const [entry] = await Promise.all([
    page.waitForResponse(response => response.url() === `${BASE}/auth/login` && response.request().method() === 'GET'),
    page.getByTestId('sign-in').click(),
  ])
  if (entry.status() !== 302) throw new Error(`Sign-in entrypoint returned HTTP ${entry.status()}`)
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
  const context = await browser.newContext({ storageState: stateFile(user), ...opts })
  const page = await context.newPage()
  if ((await context.request.get(`${BASE}/api/session`)).status() === 401) {
    // Provider logout can invalidate the BFF state saved by global setup.
    // Discard its stale SSO cookies before requiring a new login form.
    await context.clearCookies()
    await signIn(page, user)
    // Reuse the replacement rather than authenticating from the same dead
    // saved session in every subsequent test (and exhausting login limits).
    await context.storageState({ path: stateFile(user) })
    chmodSync(stateFile(user), 0o600)
  }
  return { context, page }
}
