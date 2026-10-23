import { randomUUID } from 'node:crypto'
import { expect, test } from '@playwright/test'
import { BASE, pageAs } from './auth'
import { appConfigVersion } from './kv-metadata'

for (const user of ['cleo', 'ben', 'dirk', 'ada', 'finn'] as const) {
  test(`${user}: rotation capability matches server policy`, async ({ browser }) => {
    const { context, page } = await pageAs(browser, user)
    const allowed = user === 'cleo' || user === 'dirk'
    const session = await (await context.request.get(`${BASE}/api/session`)).json()
    expect(session.roles.isOperator).toBe(allowed)
    await page.goto('/operator')
    await page.waitForLoadState('networkidle')
    await expect(page.locator('.vso-name').filter({ hasText: /^app-config$/ })).toBeVisible()
    await expect(page.getByRole('heading', { level: 1, name: 'Operator' })).toBeVisible()
    const button = page.getByRole('button', { name: 'Rotate', exact: true })
    await expect(button).toHaveCount(allowed ? 1 : 0)
    if (!allowed) {
      const version = await appConfigVersion()
      const response = await context.request.post(`${BASE}/api/v1/operator/static-secrets/app-config/rotate`, {
        headers: { Origin: BASE }, data: { operationId: randomUUID() },
      })
      expect(response.status()).toBe(403)
      expect(await appConfigVersion()).toBe(version)
    } else {
      const response = await context.request.post(`${BASE}/api/v1/operator/static-secrets/app-config/rotate`, {
        headers: { Origin: BASE }, data: { operationId: randomUUID() },
      })
      expect(response.status()).toBe(200)
      expect(await response.json()).toMatchObject({ state: 'accepted-unverified', writeConfirmed: true })
    }
    await context.close()
  })
}

test('anonymous direct mutation is denied and malicious origin is rejected', async ({ request }) => {
  const version = await appConfigVersion()
  const path = `${BASE}/api/v1/operator/static-secrets/app-config/rotate`
  expect((await request.post(path, { headers: { Origin: BASE }, data: { operationId: randomUUID() } })).status()).toBe(401)
  expect((await request.post(path, { headers: { Origin: 'https://untrusted.invalid' }, data: {} })).status()).toBe(403)
  expect(await appConfigVersion()).toBe(version)
})

test('@rotation operator receives a safe accepted-unverified receipt', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'cleo')
  const operationId = randomUUID()
  const path = `${BASE}/api/v1/operator/static-secrets/app-config/rotate`
  const first = await context.request.post(path, { headers: { Origin: BASE }, data: { operationId } })
  expect(first.status()).toBe(200)
  const receipt = await first.json()
  expect(receipt.state).toBe('accepted-unverified')
  expect(receipt).not.toHaveProperty('session_secret')
  const retry = await context.request.post(path, { headers: { Origin: BASE }, data: { operationId } })
  expect(await retry.json()).toEqual(receipt)
  await page.goto('/operator')
  await expect(page.getByRole('heading', { level: 1, name: 'Operator' })).toBeVisible()
  await context.close()
})

test('@rotation concurrent operations preserve CAS version ordering', async ({ browser }) => {
  const { context } = await pageAs(browser, 'cleo')
  const before = await appConfigVersion()
  const responses = await Promise.all(Array.from({ length: 3 }, () => context.request.post(
    `${BASE}/api/v1/operator/static-secrets/app-config/rotate`,
    { headers: { Origin: BASE }, data: { operationId: randomUUID() } },
  )))
  const versions: number[] = []
  for (const response of responses) {
    expect([200, 409]).toContain(response.status())
    if (response.status() === 200) {
      const receipt = await response.json()
      expect(receipt.writeConfirmed).toBe(true)
      versions.push(receipt.version)
    }
  }
  expect(versions.length).toBeGreaterThan(0)
  expect(new Set(versions).size).toBe(versions.length)
  expect(await appConfigVersion()).toBe(before + versions.length)
  await context.close()
})
