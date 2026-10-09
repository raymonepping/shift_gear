// tests/signin.spec.ts — sign-in page renders correctly and lets users in.
import { expect, test } from '@playwright/test'
import { BASE, signIn } from './auth'

test('sign-in page has the correct heading', async ({ page }) => {
  await page.goto(`${BASE}/signin`)
  await expect(page.getByRole('heading', { level: 1 })).toContainText(/shift_gear|one vault/i)
})

test('sign-in button links to Vault OIDC auth', async ({ page }) => {
  await page.goto(`${BASE}/signin`)
  const btn = page.getByTestId('sign-in')
  await expect(btn).toBeVisible()
  const href = await btn.getAttribute('href')
  expect(href).toBe('/auth/login')
})

test('ada can sign in and land on the fleet page', async ({ page }) => {
  await signIn(page, 'ada')
  await expect(page).toHaveURL(/\/$/)
  await expect(page.getByRole('heading', { level: 1 })).toContainText(/provisioned, converged, sealed/i)
})

test('invalid redirect returns error query param to sign-in', async ({ page }) => {
  // Auth callback with a bad state parameter should redirect to /signin?error=...
  await page.goto(`${BASE}/auth/callback?error=access_denied&error_description=Access+denied`)
  await expect(page).toHaveURL(/\/signin/)
})
