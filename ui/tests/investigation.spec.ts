import { test, expect } from '@playwright/test'
import { pageAs } from './auth'

test('runtime outages retain source identity and link to the investigation guide', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'ada')
  await page.route('**/api/v1/runtime', route => route.fulfill({ json: { sources: [
    { name: 'Vault health', owner: 'Vault', resource: 'sg-vault/vault-active', state: 'unavailable', observedAt: null, checkedAt: new Date().toISOString(), data: {} },
    { name: 'Identity discovery', owner: 'Ansible', resource: 'sg-identity/keycloak', state: 'denied', observedAt: null, checkedAt: new Date().toISOString(), data: {} },
  ] } }))
  await page.goto('/operator')
  const details = page.locator('details.runtime-sources')
  await details.locator('summary').focus()
  await page.keyboard.press('Enter')
  await expect(details).toContainText('Vault health: unavailable')
  await expect(details).toContainText('Identity discovery: denied')
  await expect(details).toContainText('Owner: Vault')
  await details.getByRole('link', { name: 'Investigation steps' }).first().click()
  await expect(page).toHaveURL(/\/help#vault$/)
  await expect(page.getByRole('heading', { name: 'Vault health · Vault / Ansible' })).toBeVisible()
  await context.close()
})

test('audit filter, paging and collector restart are visible to keyboard users', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'finn')
  let instanceId = 'before'
  await page.route('**/api/v1/audit', route => route.fulfill({ json: {
    state: 'live', collector: { instanceId, listening: true, connections: 1, received: 55, stored: 55, dropped: 0, startedAt: '2026-10-16T00:00:00Z' },
    entries: Array.from({ length: 55 }, (_, i) => ({ id: `${instanceId}:${i}`, time: '2026-10-16T00:00:00Z', type: 'request', operation: 'read', path: i < 30 ? 'kv/example' : 'transit/example', namespace: '', displayName: 'fixture', policies: [], hmacFields: [], error: null })),
  } }))
  await page.goto('/audit')
  await page.getByLabel('Path contains').fill('kv/')
  await expect(page.getByRole('status').filter({ hasText: 'Page 1' })).toContainText('30 recent entries')
  await page.getByRole('button', { name: 'Next', exact: true }).focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('status').filter({ hasText: 'Page 2' })).toBeVisible()
  await page.getByLabel('Path contains').fill('no-match')
  await expect(page.getByText('No recent entries match these filters')).toBeVisible()
  instanceId = 'after'
  await page.getByRole('button', { name: 'Refresh', exact: true }).click()
  await expect(page.getByText('Collector restarted during this visit.', { exact: false })).toBeVisible()
  await context.close()
})


test('authenticated runtime endpoint observes eleven real sources without raw data', async ({ browser }, info) => {
  const { page, context } = await pageAs(browser, 'finn')
  const response = await page.request.get('/api/v1/runtime')
  expect(response.status()).toBe(200)
  const result = await response.json()
  expect(result.sources).toHaveLength(11)
  for (const source of result.sources) {
    expect(source.state, source.name).toBe('available')
    expect(Date.now() - Date.parse(source.observedAt)).toBeLessThan(30000)
    expect(source.resource).toMatch(/^sg-/)
    expect(source.data).not.toHaveProperty('token')
    expect(source.data).not.toHaveProperty('spec')
  }
  await page.goto('/cluster')
  await expect(page.locator('.cluster-pill')).toHaveText('Seal chain 3/3')
  await expect(page.locator('.live-unsealed')).toContainText('3/3 members currently verified unsealed')
  await page.screenshot({ path: `test-results/seal-chain-${info.project.name}.png`, fullPage: true })
  await context.close()
})


test('a failed page request has an accessible retry and preserves source meaning', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'ada')
  let unavailable = true
  await page.route('**/api/v1/operator/secrets', route => unavailable
    ? route.fulfill({ status: 503, json: { message: 'fixture unavailable' } }) : route.continue())
  await page.goto('/operator')
  await expect(page.getByRole('alert')).toContainText('Operator observations could not be refreshed (HTTP 503)')
  unavailable = false
  await page.getByRole('button', { name: 'Retry observations' }).focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('alert')).not.toBeVisible()
  await expect(page.getByText('app-config', { exact: true }).first()).toBeVisible()
  await context.close()
})

test('imminent session expiry is announced without exposing credentials', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'finn')
  const session = await (await page.request.get('/api/session')).json()
  await page.route('**/api/session', route => route.fulfill({ json: { ...session, expiresAt: new Date(Date.now() + 120000).toISOString() } }))
  await page.goto('/operator')
  await expect(page.getByText(/Your session expires in about [12] minutes/)).toBeVisible()
  await expect(page.getByRole('button', { name: 'Check session' })).toBeVisible()
  await context.close()
})
