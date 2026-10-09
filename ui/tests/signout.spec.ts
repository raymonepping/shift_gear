// tests/signout.spec.ts — sign-out journey.
// Signs in fresh (does NOT reuse stored state) so the stored sessions
// that other specs depend on are never destroyed.
//
// Sign-out now redirects through Keycloak's end-session endpoint before
// returning to /signin. The URL assertion waits long enough for the
// extra Keycloak redirect to complete.
import { chromium, expect, test } from '@playwright/test'
import { BASE, signIn } from './auth'
import { passwordOf } from './users'

test('sign out lands on /signin and invalidates the session', async () => {
  // Fresh browser context — isolated from every stored state.
  const browser = await chromium.launch()
  const context = await browser.newContext({ ignoreHTTPSErrors: true })
  const page = await context.newPage()

  try {
    await signIn(page, 'ben')

    // Confirm we are signed in
    await expect(page).toHaveURL(new RegExp(`^${BASE}/?$`))

    // Click Sign out — the form submits POST /auth/logout → Keycloak
    // end-session → redirect back to /signin.
    await page.click('button.persona-out')

    // Wait through the Keycloak redirect chain back to /signin.
    await expect(page).toHaveURL(`${BASE}/signin`, { timeout: 20_000 })
    await expect(page).not.toHaveTitle(/Page not found/i)
    const bodyText = await page.textContent('body')
    expect(bodyText).not.toMatch(/page not found/i)

    // Session cookie is gone — /api/session returns 401
    const sessionResp = await page.request.get(`${BASE}/api/session`)
    expect(sessionResp.status()).toBe(401)

    // Navigating to / redirects back to /signin
    await page.goto(`${BASE}/`)
    await expect(page).toHaveURL(`${BASE}/signin`, { timeout: 10_000 })
  } finally {
    await context.close()
    await browser.close()
  }
})

// Sanity: ben's password is available (passwordOf throws if not set).
test('ben password is available for the sign-out journey', () => {
  expect(() => passwordOf('ben')).not.toThrow()
})
