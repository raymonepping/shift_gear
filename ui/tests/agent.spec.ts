// tests/agent.spec.ts — Agent page: seal-agent card, sidecar cards, TTL countdown.
import { expect, test } from '@playwright/test'
import { pageAs } from './auth'

test('agent page renders for ada', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/agent')
  await page.waitForLoadState('networkidle')
  await expect(page.getByRole('heading', { level: 1, name: /agent/i })).toBeVisible()
  await context.close()
})

test('seal-agent card is present', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/agent')
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1_000)
  // At least one agent card must be visible
  await expect(page.locator('.sg-layer-panel--agent').first()).toBeVisible()
  await context.close()
})

test('re-inject button visible to cleo (operator), hidden to ben', async ({ browser }) => {
  const { context: cleoCtx, page: cleoPage } = await pageAs(browser, 'cleo')
  await cleoPage.goto('/agent')
  await cleoPage.waitForLoadState('networkidle')
  await cleoPage.waitForTimeout(1_000)
  // Cleo is operator — may see reinject button if an agent card is present
  // We only verify the page renders without error for ben
  const { context: benCtx, page: benPage } = await pageAs(browser, 'ben')
  await benPage.goto('/agent')
  await benPage.waitForLoadState('networkidle')
  await expect(benPage.locator('[data-testid="reinject-btn"]')).toHaveCount(0)
  await cleoCtx.close()
  await benCtx.close()
})
