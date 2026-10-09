// tests/layers.spec.ts — Layers page: phases table, gates, layer badges.
import { expect, test } from '@playwright/test'
import { pageAs } from './auth'

test('phases table has all 13 phase rows', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/layers')
  await page.waitForLoadState('networkidle')
  // Wait for data to load (lazy fetch)
  await page.waitForTimeout(1_000)
  const rows = page.locator('.layer-list > li')
  await expect(rows).toHaveCount(13)
  await context.close()
})

test('gates panel is present with the four expected gates', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/layers')
  await page.waitForLoadState('networkidle')
  for (const gate of ['Idempotency', 'Drift', 'Secret scan', 'Validation']) {
    await expect(page.locator('.gate-name', { hasText: new RegExp('^' + gate + '$') })).toBeVisible()
  }
  await context.close()
})

test('Terraform phases show the tf layer badge', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'cleo')
  await page.goto('/layers')
  await page.waitForLoadState('networkidle')
  await expect(page.locator('.tool-tag.terraform').first()).toBeVisible()
  await context.close()
})
