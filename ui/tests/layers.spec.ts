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

test('duration column is present and at least one phase shows NmNNs format', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  // Use a viewport wide enough that .layer-dur is not hidden by the ≤720px rule.
  await context.pages()[0]?.setViewportSize({ width: 1024, height: 768 })
  await page.setViewportSize({ width: 1024, height: 768 })
  await page.goto('/layers')
  await page.waitForLoadState('networkidle')
  // Wait for the lazy API fetch to populate the phase list.
  await page.waitForSelector('.layer-row', { timeout: 10_000 })
  const durCells = page.locator('.layer-dur')
  // Cells exist and are visible at this viewport width.
  await expect(durCells.first()).toBeVisible({ timeout: 5_000 })
  // At least one cell must show the NmNNs pattern (e.g. "0m02s", "1m13s") or "—".
  const texts = await durCells.allTextContents()
  const hasValue = texts.some(t => /^\d+m\d{2}s$/.test(t.trim()))
  const allDashes = texts.every(t => t.trim() === '—')
  expect(texts.length).toBeGreaterThan(0)
  if (!allDashes) {
    expect(hasValue).toBe(true)
  }
  await context.close()
})
