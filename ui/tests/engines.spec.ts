// tests/engines.spec.ts — Engines page: mounted engines grid, skipped table.
import { expect, test } from '@playwright/test'
import { pageAs } from './auth'

test('engines page title is correct', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/engines')
  await expect(page).toHaveTitle(/engines/i)
  await context.close()
})

test('mounted engines section is visible', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/engines')
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1_000)
  await expect(page.getByRole('heading', { name: /^mounted engines$/i })).toBeVisible()
  await context.close()
})

test('skipped engines section is present', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/engines')
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1_000)
  await expect(page.getByRole('heading', { name: /not mounted, on purpose/i })).toBeVisible()
  await context.close()
})
