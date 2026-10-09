// tests/cluster.spec.ts — Cluster page: seal chain, 3 nodes, licence.
// @failover: kill the active pod and verify leadership moves (requires live cluster).
import { execFileSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { homedir } from 'node:os'
import { resolve } from 'node:path'
import { expect, test } from '@playwright/test'
import { pageAs } from './auth'
import { ROOT } from './users'

const CRC_OC = resolve(homedir(), '.crc/bin/oc/oc')
const OC = process.env.OC ?? (existsSync(CRC_OC) ? CRC_OC : 'oc')

test('seal chain region is rendered with Seal Vault', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'finn')
  await page.goto('/cluster')
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1_000)
  const chain = page.getByRole('region', { name: /seal chain/i })
  await expect(chain).toContainText('Seal Vault')
  await context.close()
})

test('cluster tile shows 3/3 unsealed when healthy', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'finn')
  await page.goto('/cluster')
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1_500)
  await expect(page.locator('.vg-tile', { hasText: /main cluster/i })).toContainText('3/3')
  await context.close()
})

test('licence tile is visible', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/cluster')
  await page.waitForLoadState('networkidle')
  await expect(page.locator('.vg-tile', { hasText: /licence/i })).toBeVisible()
  await context.close()
})

test('@failover deleting the leader moves leadership', async ({ browser }) => {
  test.skip(!process.env.ENABLE_FAILOVER_TEST, 'set ENABLE_FAILOVER_TEST=true to run')
  test.setTimeout(240_000)
  const { context, page } = await pageAs(browser, 'finn')
  await page.goto('/cluster')
  await page.waitForTimeout(2_000)
  const leaderNode = page.locator('.sg-chain-node[data-role="leader"] strong')
  const before = (await leaderNode.innerText()).trim()
  execFileSync(OC, ['-n', 'sg-vault', 'delete', 'pod', before, '--wait=false'], {
    env: { ...process.env, KUBECONFIG: resolve(ROOT, '.secrets/kube/config') },
  })
  await expect(async () => {
    await page.reload()
    const now = (await leaderNode.innerText({ timeout: 4_000 })).trim()
    expect(now).not.toBe(before)
  }).toPass({ timeout: 120_000, intervals: [5_000] })
  await expect(async () => {
    await page.reload()
    await expect(page.locator('.vg-tile', { hasText: /main cluster/i })).toContainText('3/3', { timeout: 4_000 })
  }).toPass({ timeout: 150_000, intervals: [5_000] })
  await context.close()
})
