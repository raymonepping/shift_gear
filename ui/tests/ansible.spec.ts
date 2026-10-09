// tests/ansible.spec.ts — Ansible page: convergence + validation panels.
import { expect, test } from '@playwright/test'
import { pageAs } from './auth'

test('ansible page is visible to ada', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/ansible')
  await page.waitForLoadState('networkidle')
  await expect(page.getByRole('heading', { level: 1, name: /ansible/i })).toBeVisible()
  await context.close()
})

test('convergence panel is present', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/ansible')
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1_000)
  await expect(page.getByRole('heading', { name: /convergence/i })).toBeVisible()
  await context.close()
})

test('validation rows table is present', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/ansible')
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1_000)
  await expect(page.getByRole('heading', { name: /validate results/i })).toBeVisible()
  await context.close()
})

test('the console never runs Ansible: no run-validate button, even for cleo (operator)', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'cleo')
  await page.goto('/ansible')
  await page.waitForLoadState('networkidle')
  await expect(page.locator('[data-testid="run-validate"]')).toHaveCount(0)
  await context.close()
})
