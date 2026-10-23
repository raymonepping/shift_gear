// tests/signout.spec.ts — sign-out journey.
// Signs in fresh (does NOT reuse stored state) so the stored sessions
// are independent; provider logout deliberately invalidates all BFF sessions
// for the subject, including sessions saved by other specs.
//
// Sign-out now redirects through Keycloak's end-session endpoint before
// returning to /signin. The URL assertion waits long enough for the
// extra Keycloak redirect to complete.
import { expect, test } from '@playwright/test'
import { BASE, signIn } from './auth'
import { passwordOf } from './users'

test('sign out lands on /signin and invalidates the session', async ({ browser, page }) => {
  // Fresh browser context — isolated from every stored state.
  const other = await browser.newContext()

  try {
    await test.step('authenticate the initiating session', () => signIn(page, 'ben'))
    expect(await (await page.request.get(`${BASE}/api/session`)).json()).toMatchObject({ username: 'ben' })
    const otherPage = await other.newPage()
    await test.step('authenticate an independent second session', () => signIn(otherPage, 'ben'))
    const secondSession = await other.request.get(`${BASE}/api/session`)
    expect(secondSession.status()).toBe(200)
    expect(await secondSession.json()).toMatchObject({ username: 'ben' })

    // Confirm we are signed in
    await expect(page).toHaveURL(new RegExp(`^${BASE}/?$`))

    // Click Sign out — the form submits POST /auth/logout → Keycloak
    // end-session. Keycloak may show a "Do you want to log out?" confirmation
    // page; if so, click through it. Then it redirects back to /signin.
    await test.step('submit logout from the initiating browser', async () => {
      await page.bringToFront()
      await page.waitForLoadState('networkidle')
      const button = page.getByRole('button', { name: 'Sign out', exact: true })
      await expect(button).toBeVisible()
      await button.click({ timeout: 10_000 })
    })
    await page.waitForLoadState('networkidle')

    // Handle optional Keycloak logout confirmation page.
    if (page.url().includes('keycloak') && page.url().includes('logout')) {
      const confirmBtn = page.locator('#kc-logout, input[type="submit"], button[type="submit"]').first()
      if (await confirmBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
        await confirmBtn.click()
      }
    }

    // Should be on /signin now.
    await expect(page).toHaveURL(`${BASE}/signin`, { timeout: 20_000 })
    await expect(page).not.toHaveTitle(/Page not found/i)
    const bodyText = await page.textContent('body')
    expect(bodyText).not.toMatch(/page not found/i)

    // Session cookie is gone — /api/session returns 401
    const sessionResp = await page.request.get(`${BASE}/api/session`)
    expect(sessionResp.status()).toBe(401)
    // Provider backchannel maps issuer+subject through Vault's OIDC metadata.
    // A second BFF session must be invalidated without using its logout route.
    await expect.poll(async () => (await other.request.get(`${BASE}/api/session`)).status(), { timeout: 20_000 }).toBe(401)

    // Navigating to / redirects back to /signin
    await page.goto(`${BASE}/`)
    await expect(page).toHaveURL(`${BASE}/signin`, { timeout: 10_000 })
  } finally {
    await other.close().catch(() => {})
  }
})

// Sanity: ben's password is available (passwordOf throws if not set).
test('ben password is available for the sign-out journey', () => {
  expect(() => passwordOf('ben')).not.toThrow()
})
