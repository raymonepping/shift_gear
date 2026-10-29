// Engines › Rotation while the KV rotation add-on is NOT installed (ADR D17):
// no nav item, an honest page (never a 404), and history still read from Vault.
import { expect, test } from '@playwright/test'
import { BASE, pageAs } from './auth'

test('@kv-rotation not installed: no nav item, honest page', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'cleo')
  const features = await (await context.request.get(`${BASE}/api/features`)).json()
  test.skip(features.rotation !== 'not-installed', 'KV rotation add-on is installed')
  await page.goto('/engines')
  await expect(page.getByText(/KV rotation add-on: not installed/)).toBeVisible()
  await expect(page.locator('.sidebar-nav').getByRole('link', { name: 'Rotation' })).toHaveCount(0)
  await page.goto('/engines/rotation')
  await expect(page.getByRole('heading', { level: 1, name: 'Rotation' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'The KV rotation add-on is not installed' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Rotate now' })).toHaveCount(0)
  await context.close()
})
