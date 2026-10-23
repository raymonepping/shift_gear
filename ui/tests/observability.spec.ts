import { expect, test } from '@playwright/test'
import { BASE, pageAs } from './auth'
import { METRICS, type ObservabilityResponse } from '../shared/observability'

test('observability API authenticates, fixes its upstream query and projects retained fields', async ({ browser }) => {
  const anon = await browser.newContext()
  expect((await anon.request.get(`${BASE}/api/v1/observability`)).status()).toBe(401)
  await anon.close()
  const { page, context } = await pageAs(browser, 'finn')
  expect((await page.request.get('/api/v1/observability?query=up')).status()).toBe(400)
  expect((await page.request.get('/api/v1/observability?url=http://example.invalid')).status()).toBe(400)
  const write = await page.request.post('/api/v1/observability', { headers: { origin: new URL(BASE).origin }, data: {} })
  expect(write.status()).toBe(405)
  expect(write.headers().allow).toBe('GET, HEAD')
  const response = await page.request.get('/api/v1/observability')
  expect(response.status()).toBe(200)
  const body = await response.json() as ObservabilityResponse
  expect(body.metrics.state).toBe(body.metrics.backend === 'none' ? 'disabled' : 'available')
  if (body.metrics.backend !== 'none') {
  expect(body.metrics.samples.map(row => row.name).sort()).toEqual([...METRICS].sort())
  expect(body.metrics.samples.find(row => row.name === 'up')?.value).toBe(1)
  }
  expect(['disabled', 'available']).toContain(body.archive.state)
  if (body.archive.state === 'available') {
  expect(body.archive.status?.available).toBe(true)
  expect(body.archive.entries.length).toBeGreaterThan(0)
  for (const row of body.archive.entries) {
    expect(Object.keys(row).sort()).toEqual(['hasError', 'id', 'namespace', 'operation', 'path', 'retainedAt', 'time', 'type'])
  }
  }
  await context.close()
})

test('retained view filters with keyboard and links to its source runbook', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'finn')
  await page.goto('/audit')
  await page.getByRole('link', { name: 'Metrics and retained audit metadata' }).focus()
  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(/\/observability$/)
  const selected = await (await page.request.get('/api/v1/observability')).json() as ObservabilityResponse
  if (selected.metrics.backend === 'none') await expect(page.getByText('Metrics integration is disabled.', { exact: false })).toBeVisible()
  else {
    const metrics = page.getByRole('region', { name: 'Numeric metric samples' })
    await expect(metrics).toContainText('sg_audit_archive_bytes')
    if ((page.viewportSize()?.width ?? 1000) < 760) {
      expect(await metrics.evaluate(element => element.scrollWidth > element.clientWidth)).toBe(true)
      await metrics.focus()
      await page.keyboard.press('ArrowRight')
      await expect.poll(() => metrics.evaluate(element => element.scrollLeft)).toBeGreaterThan(0)
    }
  }
  if (selected.archive.state === 'available') {
  const table = page.getByRole('region', { name: 'Retained metadata entries' })
  await expect(table).toHaveAccessibleDescription('Scroll inside the table to review retained records; the path filter narrows this view.')
  expect(await table.evaluate(element => element.clientHeight)).toBeLessThanOrEqual(512)
  await table.focus()
  await page.keyboard.press('End')
  await expect.poll(() => table.evaluate(element => element.scrollHeight <= element.clientHeight || element.scrollTop > 0)).toBe(true)
  await page.getByLabel('Retained path contains').fill('no-matching-retained-fixture-928374')
  await expect(page.getByText('No retained records match this view.')).toBeVisible()
  } else await expect(page.getByText('Audit archive is disabled.', { exact: false })).toBeVisible()
  await page.getByRole('link', { name: 'Metrics and retention runbook' }).focus()
  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(/\/help#observability$/)
  await context.close()
})

for (const missing of ['metrics', 'archive'] as const) {
  test(`observability isolates ${missing} failure and preserves stale sample time`, async ({ browser }) => {
    const { page, context } = await pageAs(browser, 'ada')
    const sampleAt = '2020-01-01T00:00:00.000Z'
    const body: ObservabilityResponse = {
      checkedAt: new Date().toISOString(),
      metrics: { backend: 'opentelemetry', state: missing === 'metrics' ? 'unavailable' : 'available', samples: missing === 'metrics' ? [] : [{ name: 'up', value: 1, at: sampleAt }] },
      archive: { state: missing === 'archive' ? 'unavailable' : 'available', status: missing === 'archive' ? null : { available: false, committed: 1, failed: 1, queueDropped: 0, corrupt: 0, pruned: 0, bytes: 200, retained: 1, queued: 0, maxBytes: 67108864, retentionSeconds: 604800, oldestAt: null, lastCommittedAt: null }, entries: [] },
    }
    await page.route('**/api/v1/observability', route => route.fulfill({ json: body }))
    await page.goto('/observability')
    if (missing === 'metrics') {
      await expect(page.getByText('Metrics cannot currently be verified.')).toBeVisible()
      await expect(page.getByLabel('Retained path contains')).toBeVisible()
      await expect(page.getByText('Archive storage is unavailable.', { exact: false })).toBeVisible()
      await expect(page.getByText('Archive gaps or corruption recorded in this process:', { exact: false })).toBeVisible()
    } else {
      await expect(page.getByText('Retained metadata cannot currently be read.', { exact: false })).toBeVisible()
      await expect(page.getByRole('region', { name: 'Numeric metric samples' })).toContainText(sampleAt)
      await expect(page.getByText('Stale or clock uncertain', { exact: true })).toBeVisible()
    }
    await context.close()
  })
}

test('disabled telemetry is explicit and leaves the live audit link available', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'ada')
  await page.route('**/api/v1/observability', route => route.fulfill({ json: {
    checkedAt: new Date().toISOString(), metrics: { backend: 'none', state: 'disabled', samples: [] },
    archive: { state: 'disabled', status: null, entries: [] },
  } }))
  await page.goto('/observability')
  await expect(page.getByText('Metrics integration is disabled.', { exact: false })).toBeVisible()
  await expect(page.getByText('Audit archive is disabled.', { exact: false })).toBeVisible()
  await expect(page.getByText('Metrics cannot currently be verified.')).not.toBeVisible()
  await page.getByRole('link', { name: 'Back to the live audit feed' }).click()
  await expect(page).toHaveURL(/\/audit$/)
  await context.close()
})
