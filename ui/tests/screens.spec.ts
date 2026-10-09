// tests/screens.spec.ts — @screens: screenshot every page at 1440×900 and
// 390×844 → docs/screenshots/ui/. Run with: make ui-screens
import { mkdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { test } from '@playwright/test'
import { BASE, pageAs } from './auth'
import { ROOT } from './users'

const OUT = resolve(ROOT, 'docs/screenshots/ui')

const SCREENS: [string, string][] = [
  ['fleet', '/'],
  ['layers', '/layers'],
  ['engines', '/engines'],
  ['pods', '/pods'],
  ['routes', '/routes'],
  ['operator', '/operator'],
  ['ansible', '/ansible'],
  ['agent', '/agent'],
  ['audit', '/audit'],
  ['cluster', '/cluster'],
]

for (const [w, h, suffix] of [[1440, 900, 'desktop'], [390, 844, 'mobile']] as const) {
  test(`@screens ${suffix}`, async ({ browser }) => {
    test.setTimeout(240_000)
    mkdirSync(OUT, { recursive: true })

    // Sign-in page (unauthenticated)
    const anon = await browser.newContext({ viewport: { width: w, height: h }, ignoreHTTPSErrors: true })
    const lp = await anon.newPage()
    await lp.goto(`${BASE}/signin`)
    await lp.waitForLoadState('networkidle')
    await lp.screenshot({ path: `${OUT}/signin-${suffix}.png`, fullPage: true })
    await anon.close()

    // All app pages as ada
    const { context, page } = await pageAs(browser, 'ada', { viewport: { width: w, height: h } })
    for (const [name, route] of SCREENS) {
      await page.goto(route)
      await page.waitForLoadState('networkidle')
      await page.waitForTimeout(1_200)
      await page.screenshot({ path: `${OUT}/${name}-${suffix}.png`, fullPage: true })
    }
    await context.close()
  })
}
