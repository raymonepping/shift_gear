// tests/pods.spec.ts — Pods page: pod cards with 4-indicator grid.
import { expect, test } from '@playwright/test'
import { pageAs } from './auth'

test('pods page renders for ada', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/pods')
  await page.waitForLoadState('networkidle')
  await expect(page.getByRole('heading', { level: 1, name: /pods/i })).toBeVisible()
  await context.close()
})

test('pod cards section is present', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/pods')
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1_000)
  // Either a list of pod cards or an empty-state message must be present
  const cards = page.locator('.instance-card')
  const emptyState = page.locator('.state-empty')
  const count = await cards.count()
  if (count === 0) await expect(emptyState).toBeVisible()
  else await expect(cards.first()).toBeVisible()
  await context.close()
})

test('routes page renders correctly', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/routes')
  await page.waitForLoadState('networkidle')
  await expect(page.getByRole('heading', { level: 1, name: /routes/i })).toBeVisible()
  await context.close()
})
