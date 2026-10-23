import { test, expect } from '@playwright/test'
import { pageAs } from './auth'
import { sealSourceNames } from '../shared/seal-chain'

function healthySources(at = new Date().toISOString()) {
  return sealSourceNames.map((name, index) => ({ name, owner: 'fixture', resource: 'fixed', state: 'available',
    observedAt: at, checkedAt: at, data: index === 1 ? { available: true }
      : { initialized: true, sealed: false, standby: index > 2, performanceStandby: false } }))
}

test('live chain stays verified beyond the snapshot freshness window without host publication', async ({ browser }, info) => {
  test.skip(info.project.name !== 'chromium', 'one real-time observation window covers the shared polling loop')
  test.setTimeout(180000)
  const { page, context } = await pageAs(browser, 'finn')
  // Keep the actual published observation old; runtime requests go to the real BFF.
  await page.route('**/api/v1/fleet', async route => {
    const response = await route.fetch()
    const body = await response.json()
    body.observedAt = new Date(Date.now() - 3600000).toISOString()
    body.evidence = { ...body.evidence, observedAt: body.observedAt, freshness: 'stale' }
    await route.fulfill({ json: body })
  })
  const observations: string[] = []
  page.on('response', async response => {
    if (response.url().endsWith('/api/v1/runtime') && response.ok()) {
      const result = await response.json().catch(() => null)
      const at = result?.sources.find((source: { name: string }) => source.name === 'Seal Vault')?.observedAt
      if (at) observations.push(at)
    }
  })
  await page.goto('/')
  const pill = page.locator('.cluster-pill')
  await expect(pill).toHaveText('Seal chain 3/3')
  await expect(page.getByText('Published snapshot is not current', { exact: true })).toBeVisible()
  await page.waitForTimeout(125000)
  await expect(pill).toHaveText('Seal chain 3/3')
  expect(new Set(observations).size).toBeGreaterThanOrEqual(6)
  expect(Date.now() - Date.parse(observations.at(-1)!)).toBeLessThan(30000)
  await context.close()
})

test('Agent failure cannot hide behind three unsealed members and recovers on the next read', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'finn')
  let agentReady = false
  await page.route('**/api/v1/runtime', route => {
    const sources = healthySources()
    sources[1]!.data = { available: agentReady }
    return route.fulfill({ json: { sources } })
  })
  await page.goto('/cluster')
  await expect(page.locator('.cluster-pill')).toHaveText('Seal Agent unavailable')
  agentReady = true
  await page.getByRole('button', { name: 'Check seal chain', exact: true }).click()
  await expect(page.locator('.cluster-pill')).toHaveText('Seal chain 3/3')
  await context.close()
})

test('failed runtime refresh withdraws green and a subsequent successful read restores it', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'finn')
  let fail = false
  await page.route('**/api/v1/runtime', route => fail ? route.fulfill({ status: 503, json: {} })
    : route.fulfill({ json: { sources: healthySources() } }))
  await page.goto('/')
  await expect(page.locator('.cluster-pill')).toHaveText('Seal chain 3/3')
  fail = true
  await page.getByRole('button', { name: 'Check seal chain', exact: true }).click()
  await expect(page.locator('.cluster-pill')).toHaveText('Seal chain: not currently verified')
  fail = false
  await page.getByRole('button', { name: 'Check seal chain', exact: true }).click()
  await expect(page.locator('.cluster-pill')).toHaveText('Seal chain 3/3')
  await context.close()
})

test('retained responses expire by observation time even if the endpoint still answers', async ({ browser }) => {
  const { page, context } = await pageAs(browser, 'finn')
  const sources = healthySources()
  await page.route('**/api/v1/runtime', route => route.fulfill({ json: { sources } }))
  await page.goto('/')
  await expect(page.locator('.cluster-pill')).toHaveText('Seal chain 3/3')
  await page.clock.install()
  await page.clock.fastForward(31000)
  await expect(page.locator('.cluster-pill')).toHaveText('Seal chain: not currently verified')
  await expect(page.getByRole('region', { name: 'Seal chain', exact: true })).toContainText('not verified')
  await context.close()
})
