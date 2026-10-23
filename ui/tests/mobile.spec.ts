import { expect, test } from '@playwright/test'
import { pageAs } from './auth'

for (const width of [390, 320, 195]) {
  // 195 CSS pixels covers 390px at 200% browser zoom's effective viewport.
  test(`shell contains document at ${width} CSS pixels`, async ({ browser }) => {
    const { context, page } = await pageAs(browser, 'ada', { viewport: { width, height: 844 } })
    for (const route of ['/', '/layers', '/operator', '/audit', '/agent', '/cluster', '/engines', '/help', '/explorer', '/observability']) {
      await page.goto(route)
      await page.waitForLoadState('networkidle')
      await expect(page.getByRole('main')).toBeVisible()
      const layout = await page.evaluate(() => ({
        contained: document.documentElement.scrollWidth <= innerWidth + 1,
        overflow: [...document.querySelectorAll('main *')].filter(element => !element.closest('.vg-table-wrap')
          && element.getBoundingClientRect().right > innerWidth + 1).slice(0, 12).map(element => ({
          tag: element.tagName, class: element.className, right: element.getBoundingClientRect().right,
        })),
      }))
      expect(layout.contained, `${route}: ${JSON.stringify(layout.overflow)}`).toBe(true)
    }
    await context.close()
  })
}
