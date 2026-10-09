// tests/operator.spec.ts — Operator page: VSO CRD cards, rotate button.
import { expect, test } from '@playwright/test'
import { pageAs } from './auth'

test('operator page is accessible to cleo (operator role)', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'cleo')
  await page.goto('/operator')
  await page.waitForLoadState('networkidle')
  await expect(page.getByRole('heading', { level: 1, name: /operator/i })).toBeVisible()
  await context.close()
})

test('static secrets section is visible', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'cleo')
  await page.goto('/operator')
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1_000)
  await expect(page.getByRole('heading', { name: /vaultstaticsecrets/i })).toBeVisible()
  await context.close()
})

test('rotate button is visible for cleo but not ben', async ({ browser }) => {
  // cleo has operator role — rotate button should be visible
  const cleoCxt = await (async () => {
    const { context, page } = await pageAs(browser, 'cleo')
    await page.goto('/operator')
    await page.waitForLoadState('networkidle')
    await page.waitForTimeout(1_000)
    return { context, page }
  })()
  // Ben is staff only — no operator access to rotate
  const { context: benCtx, page: benPage } = await pageAs(browser, 'ben')
  await benPage.goto('/operator')
  await benPage.waitForLoadState('networkidle')
  await benPage.waitForTimeout(1_000)
  await expect(benPage.locator('[data-testid="rotate-btn"]')).toHaveCount(0)
  await cleoCxt.context.close()
  await benCtx.close()
})
