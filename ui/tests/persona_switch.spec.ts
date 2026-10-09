// Persona switch: sign in as ada, sign out, sign in as ben.
// Proves that sign-out fully clears state and a different persona can sign in.
// Both sign-ins use fresh Keycloak authentication (no stored state dependency).
import { chromium, expect, test } from '@playwright/test'
import { BASE, signIn } from './auth'

test('ada signs out, ben signs in — session is clean between personas', async () => {
  const browser = await chromium.launch()
  // Desktop viewport — .persona-name has display:none at ≤720px.
  const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 800 } })
  const page = await context.newPage()

  try {
    // Step 1: sign in as ada via Keycloak
    await signIn(page, 'ada')
    await expect(page).toHaveURL(new RegExp(`^${BASE}/?$`))
    // Poll /api/session until it returns 200 with ada's data.
    // useAuth.load() is called lazily after mount; polling is more reliable than a DOM wait.
    let adaSession: { username: string; displayName: string } | null = null
    for (let i = 0; i < 20; i++) {
      const r = await page.request.get(`${BASE}/api/session`)
      if (r.status() === 200) { adaSession = await r.json(); break }
      await page.waitForTimeout(500)
    }
    console.warn(`[1] session: username="${adaSession?.username}" displayName="${adaSession?.displayName}"`)
    expect(adaSession?.username.toLowerCase()).toBe('ada')
    // ada's display name comes from given_name via claim_mappings
    expect(adaSession?.displayName.toLowerCase()).toContain('ada')

    // Step 2: sign out as ada
    await page.click('button.persona-out')
    await expect(page).toHaveURL(`${BASE}/signin`, { timeout: 10_000 })
    await expect(page.locator('body')).not.toContainText(/page not found/i)
    // Session must be gone
    const logoutCheck = await page.request.get(`${BASE}/api/session`)
    expect(logoutCheck.status()).toBe(401)
    console.warn('[2] signed out — /api/session → 401 ✓')

    // Step 3: sign in as ben via Keycloak (same browser context, clean session)
    await signIn(page, 'ben')
    await expect(page).toHaveURL(new RegExp(`^${BASE}/?$`))
    let benSession: { username: string; displayName: string } | null = null
    for (let i = 0; i < 20; i++) {
      const r = await page.request.get(`${BASE}/api/session`)
      if (r.status() === 200) { benSession = await r.json(); break }
      await page.waitForTimeout(500)
    }
    console.warn(`[3] session: username="${benSession?.username}" displayName="${benSession?.displayName}"`)
    expect(benSession?.username.toLowerCase()).toBe('ben')
    // ben has no given_name in LDAP — displayName falls back to username
    expect(benSession?.displayName.toLowerCase()).toBe('ben')
  } finally {
    await context.close()
    await browser.close()
  }
})
