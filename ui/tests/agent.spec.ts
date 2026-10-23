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

test('re-injection is visibly unsupported for an operator', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'cleo')
  await page.goto('/agent')
  for (const name of ['agent-demo', 'sg-agent-db']) {
    const card = page.locator('article').filter({ has: page.getByRole('heading', { name, exact: true }) })
    await expect(card.getByRole('button', { name: 'Re-injection unavailable' })).toBeDisabled()
    await expect(card.getByRole('note')).toContainText('cannot restart Agent pods')
  }
  await context.close()
})
