// tests/links.spec.ts — no link or form in the app shell leads to a 404.
// Uses page.goto() for every same-origin link so that client-rendered Nuxt 404
// pages (status 200, body "Page not found") are caught as well as server 404s.
import { expect, test } from '@playwright/test'
import { BASE, pageAs } from './auth'

test('no shell link returns 404 or shows the error page', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  try {
    await page.goto(`${BASE}/`)
    await page.waitForLoadState('networkidle')

    // Collect all unique same-origin link paths from the rendered shell.
    const links = await page.evaluate((base) => {
      const seen = new Set<string>()
      document.querySelectorAll('a[href]').forEach((el) => {
        const url = new URL((el as HTMLAnchorElement).href, base)
        if (url.origin === new URL(base).origin) seen.add(url.pathname)
      })
      return [...seen]
    }, BASE)

    // Collect non-logout form actions (logout is covered by signout.spec.ts).
    const forms = await page.evaluate((base) => {
      const result: Array<{ action: string; method: string }> = []
      document.querySelectorAll('form[action]').forEach((el) => {
        const f = el as HTMLFormElement
        const url = new URL(f.action, base)
        if (url.origin === new URL(base).origin && url.pathname !== '/auth/logout') {
          result.push({ action: url.pathname, method: (f.method || 'get').toUpperCase() })
        }
      })
      return result
    }, BASE)

    // Navigate to each link with page.goto() so the client router runs and
    // Nuxt can render a client-side 404 page. A raw fetch would return 200
    // with the SPA shell even for an unknown route — and miss the "Page not
    // found" text that only appears after the client router runs.
    for (const path of links) {
      const resp = await page.goto(`${BASE}${path}`)
      expect(resp?.status(), `link ${path} returned HTTP ${resp?.status()}`).not.toBe(404)
      expect(resp?.status(), `link ${path} returned HTTP ${resp?.status()}`).not.toBe(405)
      // Client-rendered 404: Nuxt renders "Page not found" inside a 200 response.
      const bodyText = await page.textContent('body')
      expect(bodyText, `link ${path} shows a Nuxt 404 page`).not.toMatch(/Page not found/i)
    }

    // Forms: send the declared method; a missing server route returns 404/405.
    // The logout form is excluded — a POST to /auth/logout from here would sign
    // out ada and break every subsequent test in the suite.
    for (const { action, method } of forms) {
      const resp = method === 'POST'
        ? await page.request.post(`${BASE}${action}`)
        : await page.request.get(`${BASE}${action}`)
      expect(resp.status(), `form ${method} ${action} returned ${resp.status()}`).not.toBe(404)
      expect(resp.status(), `form ${method} ${action} returned ${resp.status()}`).not.toBe(405)
    }

    console.warn(`links.spec: checked ${links.length} link(s): ${links.join(', ')}`)
    console.warn(`links.spec: checked ${forms.length} non-logout form(s)`)
  } finally {
    await context.close()
  }
})
