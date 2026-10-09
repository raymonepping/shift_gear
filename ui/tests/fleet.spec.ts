// tests/fleet.spec.ts — Fleet dashboard: tiles, seal chain diagram, summaries.
import { expect, test } from '@playwright/test'
import { pageAs } from './auth'

test('fleet tiles are visible for ada', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/')
  await page.waitForLoadState('networkidle')
  // At least one tile labelled "Vault cluster" must be present
  await expect(page.locator('.vg-tile', { hasText: /vault cluster/i }).first()).toBeVisible()
  await context.close()
})

test('seal chain diagram is rendered', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/')
  await page.waitForLoadState('networkidle')
  await expect(page.getByRole('region', { name: /seal chain/i })).toBeVisible()
  await context.close()
})

test('finn can see fleet (auditor role)', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'finn')
  await page.goto('/')
  await page.waitForLoadState('networkidle')
  await expect(page.locator('.sg-shell')).toBeVisible()
  await context.close()
})

test('unauthenticated user is redirected to sign-in', async ({ browser }) => {
  const context = await browser.newContext({ ignoreHTTPSErrors: true })
  const page = await context.newPage()
  await page.goto('/')
  await expect(page).toHaveURL(/\/signin/)
  await context.close()
})
