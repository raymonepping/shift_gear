// tests/links.spec.ts — no link or form in the app shell leads to a 404.
// Navigates to every same-origin href in the topbar, sidebar and footer on
// the home page and expects no 404/405 response and no Nuxt error page.
import { expect, test } from '@playwright/test'
import { BASE, pageAs } from './auth'

test('no shell link returns 404 or shows the error page', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  try {
    await page.goto(`${BASE}/`)
    await page.waitForLoadState('networkidle')

    // Collect all unique same-origin hrefs from the shell
    const links = await page.evaluate((base) => {
      const seen = new Set<string>()
      document.querySelectorAll('a[href]').forEach((el) => {
        const href = (el as HTMLAnchorElement).href
        if (href.startsWith(base) || href.startsWith('/')) {
          const url = new URL(href, base)
          // Only same origin
          if (url.origin === new URL(base).origin) seen.add(url.pathname)
        }
      })
      return [...seen]
    }, BASE)

    // Collect form actions (excluding /auth/logout — covered by signout.spec.ts)
    const forms = await page.evaluate((base) => {
      const seen = new Set<{ action: string; method: string }>()
      document.querySelectorAll('form[action]').forEach((el) => {
        const f = el as HTMLFormElement
        const url = new URL(f.action, base)
        if (url.origin === new URL(base).origin && f.action !== '/auth/logout') {
          seen.add({ action: url.pathname, method: (f.method || 'get').toUpperCase() })
        }
      })
      return [...seen]
    }, BASE)

    // Check every link
    for (const path of links) {
      const resp = await page.request.get(`${BASE}${path}`)
      // SPA routes come back as 200 with HTML; server routes vary. We only
      // reject 404 and 405 status codes.
      expect(resp.status(), `link ${path} returned ${resp.status()}`).not.toBe(404)
      expect(resp.status(), `link ${path} returned ${resp.status()}`).not.toBe(405)

      // Client-rendered 404 pages: the body must not contain "Page not found"
      if (resp.headers()['content-type']?.includes('text/html')) {
        const body = await resp.text()
        expect(body, `link ${path} shows a Nuxt 404 page`).not.toMatch(/Page not found/i)
      }
    }

    // Check every non-logout form
    for (const { action, method } of forms) {
      const resp = method === 'POST'
        ? await page.request.post(`${BASE}${action}`)
        : await page.request.get(`${BASE}${action}`)
      expect(resp.status(), `form ${method} ${action} returned ${resp.status()}`).not.toBe(404)
      expect(resp.status(), `form ${method} ${action} returned ${resp.status()}`).not.toBe(405)
    }

    // Report what was found (visible in test output)
    console.warn(`links.spec: checked ${links.length} link(s): ${links.join(', ')}`)
    console.warn(`links.spec: checked ${forms.length} non-logout form(s)`)
  } finally {
    await context.close()
  }
})
