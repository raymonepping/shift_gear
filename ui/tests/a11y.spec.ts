// tests/a11y.spec.ts — axe WCAG 2.1 A/AA on every screen for ada and finn,
// plus the sign-in page — at desktop and phone viewports, with reduced motion.
// 0 violations required.
import AxeBuilder from '@axe-core/playwright'
import { expect, test, type Page } from '@playwright/test'
import { BASE, pageAs } from './auth'

const ROUTES = [
  '/', '/layers', '/engines', '/pods', '/routes',
  '/operator', '/ansible', '/agent', '/audit', '/cluster',
]
const VIEWPORTS = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

async function scan(page: Page, label: string) {
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(700)
  const { violations } = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze()
  const summary = violations.map(v => `${label} [${v.id}] (${v.impact}) ${v.nodes[0]?.target.join(' ')}`)
  expect(summary, summary.join('\n')).toEqual([])
}

for (const vp of VIEWPORTS) {
  for (const reducedMotion of ['no-preference', 'reduce'] as const) {
    const tag = `${vp.width}px${reducedMotion === 'reduce' ? ' reduced-motion' : ''}`

    test(`sign-in page — ${tag}`, async ({ browser }) => {
      const context = await browser.newContext({ viewport: vp, reducedMotion, ignoreHTTPSErrors: true })
      const page = await context.newPage()
      await page.goto(`${BASE}/signin`)
      await scan(page, '/signin')
      await context.close()
    })

    for (const user of ['ada', 'finn'] as const) {
      test(`every screen as ${user} — ${tag}`, async ({ browser }) => {
        test.setTimeout(180_000)
        const { context, page } = await pageAs(browser, user, { viewport: vp, reducedMotion })
        for (const route of ROUTES) {
          await page.goto(route)
          await scan(page, `${user} ${route}`)
        }
        await context.close()
      })
    }
  }
}
