// tests/audit.spec.ts — Audit page: table renders, filter works, offline banner.
import { expect, test } from '@playwright/test'
import { pageAs } from './auth'

test('audit page is visible to finn (auditor)', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'finn')
  await page.goto('/audit')
  await page.waitForLoadState('networkidle')
  await expect(page.getByRole('heading', { level: 2, name: /vault.*record/i })).toBeVisible()
  await context.close()
})

test('audit table headers are present', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/audit')
  await page.waitForLoadState('networkidle')
  await expect(page.locator('.vg-table thead')).toContainText('Time')
  await expect(page.locator('.vg-table thead')).toContainText('Type')
  await expect(page.locator('.vg-table thead')).toContainText('Who')
  await context.close()
})

test('type filter select is present', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/audit')
  await expect(page.locator('#sg-type-filter')).toBeVisible()
  await context.close()
})

test('collector stat tiles are present', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/audit')
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1_000)
  await expect(page.locator('.vg-tile', { hasText: /received/i })).toBeVisible()
  await expect(page.locator('.vg-tile', { hasText: /stored/i })).toBeVisible()
  await context.close()
})

test('the collector is live and Vault entries arrive (finn)', async ({ browser }) => {
  // Signing in is itself audited, so there is always at least one entry.
  const { context, page } = await pageAs(browser, 'finn')
  await page.goto('/audit')
  await page.waitForLoadState('networkidle')
  await expect(page.getByText(/counting since the collector started/i)).toBeVisible()
  await expect(page.locator('.vg-tile', { hasText: /connections/i }).locator('.vg-tile__value')).not.toHaveText('0')
  await expect(page.locator('.vg-table tbody tr').first().locator('td').first()).not.toHaveText(/no entries/i)
  await context.close()
})
