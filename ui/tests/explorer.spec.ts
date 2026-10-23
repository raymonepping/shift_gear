import { test, expect } from '@playwright/test'
import { pageAs, BASE } from './auth'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { ROOT } from './users'

const source = (name: string) => readFileSync(`${ROOT}/policies/${name}`, 'utf8')

test('published explorer binds declared sources and rejects unauthenticated or parameterized access', async ({ browser }) => {
  const anon = await browser.newContext()
  expect((await anon.request.get(`${BASE}/api/v1/explorer`)).status()).toBe(401)
  await anon.close()
  const { page, context } = await pageAs(browser, 'finn')
  const response = await page.request.get('/api/v1/explorer')
  expect(response.status()).toBe(200)
  const result = await response.json()
  expect(result.state).toBe('published')
  expect(result.evidence.source).toBe('snapshot')
  expect(result.evidence.observationId).toBeTruthy()
  expect(result.declaration.boundary).toEqual(JSON.parse(source('boundary-matrix.json')))
  expect(result.declaration.ownership).toEqual(JSON.parse(source('ownership-map.json')).rows)
  for (const item of Object.values(result.declaration.sources) as { path: string; sha256: string }[]) {
    expect(item.sha256).toBe(createHash('sha256').update(readFileSync(`${ROOT}/${item.path}`)).digest('hex'))
  }
  expect(Object.keys(result.declaration).sort()).toEqual(['boundary', 'inputDigest', 'ownership', 'schemaVersion', 'sources'])
  expect(result.declaration.inputDigest).toMatch(/^[a-f0-9]{64}$/)
  expect(result.evidence.clusterId).toBeTruthy()
  expect(result.evidence.runId).toBeTruthy()
  expect((await page.request.get('/api/v1/explorer?path=sys/policies/acl')).status()).toBe(400)
  expect((await page.request.post('/api/v1/explorer', { data: {} })).status()).toBe(403)
  const write = await page.request.post('/api/v1/explorer', { headers: { origin: new URL(BASE).origin }, data: { path: 'sys/policies/acl' } })
  expect(write.status()).toBe(405)
  expect(write.headers().allow).toBe('GET, HEAD')
  await context.close()
})

test('auditor explores ownership and expected denies with keyboard filters and runbook links', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'finn')
  await page.goto('/explorer')
  await expect(page.getByRole('heading', { name: 'Policy and ownership', exact: true })).toBeVisible()
  await expect(page.getByText('not a live capability check', { exact: false })).toBeVisible()
  await page.getByLabel('Owner', { exact: true }).selectOption('VSO')
  await expect(page.getByRole('article')).toHaveCount(1)
  await expect(page.getByRole('article')).toContainText('Application secret delivery')
  await page.getByRole('link', { name: 'Investigation steps for Application secret delivery' }).focus()
  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(/\/help#delivery$/)
  await page.goto('/explorer')
  await page.getByLabel('Maintenance identity').selectOption('tf-platform')
  await page.getByLabel('Expectation', { exact: true }).selectOption('deny')
  await expect(page.getByRole('region', { name: 'Expected capability operations' }).locator('tbody tr')).toHaveCount(3)
  await page.getByLabel('Declared path contains').fill('no-matching-declaration')
  await expect(page.getByText('No declared operations match these filters.')).toBeVisible()
  await page.getByLabel('Declared path contains').fill('')
  await expect(page.getByText('3 of 19 expected operations')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Declaration provenance' })).toBeVisible()
  await context.close()
})

test('missing declarations and failed reload never become a live permission claim', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'ada')
  await page.route('**/api/v1/explorer', route => route.fulfill({ json: { state: 'unavailable', declaration: null } }))
  await page.goto('/explorer')
  await expect(page.getByRole('heading', { name: 'Declarations unavailable' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Expected capability matrix' })).not.toBeVisible()
  await page.unroute('**/api/v1/explorer')
  await page.reload()
  await expect(page.getByRole('heading', { name: 'Expected capability matrix' })).toBeVisible()
  await page.route('**/api/v1/explorer', route => route.fulfill({ status: 503, json: { message: 'fixture unavailable' } }))
  await page.getByRole('button', { name: 'Reload published declarations' }).click()
  await expect(page.getByRole('alert')).toContainText('HTTP 503')
  await page.unroute('**/api/v1/explorer')
  await page.getByRole('button', { name: 'Retry observations' }).focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('alert')).not.toBeVisible()
  await expect(page.getByRole('heading', { name: 'Expected capability matrix' })).toBeVisible()
  await context.close()
})


test('historical explorer publication stays a snapshot with stale provenance', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'finn')
  const published = await (await page.request.get('/api/v1/explorer')).json()
  published.evidence.freshness = 'stale'
  published.evidence.observedAt = '2026-01-01T00:00:00Z'
  await page.route('**/api/v1/explorer', route => route.fulfill({ json: published }))
  await page.goto('/explorer')
  const provenance = page.getByRole('region', { name: 'Declaration provenance' })
  await expect(provenance).toContainText('at last reload: stale')
  await expect(provenance).toContainText('2026-01-01T00:00:00Z')
  await expect(page.getByRole('heading', { name: 'Expected capability matrix' })).toBeVisible()
  await context.close()
})
