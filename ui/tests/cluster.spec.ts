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
  test.setTimeout(420_000)
  // The seal diagram reads live member health, independent of host publication.
  const ocEnv = { ...process.env, KUBECONFIG: resolve(ROOT, '.secrets/kube/config') }
  const liveLeaderExcept = (excluded: string) => {
    for (const pod of ['vault-0', 'vault-1', 'vault-2']) {
      if (pod === excluded) continue
      try {
        const status = JSON.parse(execFileSync(
          OC,
          ['-n', 'sg-vault', 'exec', pod, '--', 'vault', 'status', '-format=json'],
          { encoding: 'utf8', timeout: 15_000, env: ocEnv, stdio: ['ignore', 'pipe', 'ignore'] },
        ))
        if (status.is_self) return pod
      } catch {
        // The pod can be unavailable while Raft elects the replacement leader.
      }
    }
    return ''
  }
  const { context, page } = await pageAs(browser, 'finn')
  await page.goto('/cluster')
  const leaderNode = page.locator('.sg-chain-node[data-role="leader"] strong')
  await expect(leaderNode).toHaveCount(1)
  const before = (await leaderNode.innerText()).trim()
  await expect(async () => {
    await page.reload()
    await expect(leaderNode).toHaveText(before, { timeout: 4_000 })
  }).toPass({ timeout: 150_000, intervals: [5_000] })
  execFileSync(OC, ['-n', 'sg-vault', 'delete', 'pod', before, '--wait=false'], {
    env: ocEnv,
  })
  execFileSync(OC, ['-n', 'sg-vault', 'wait', `pod/${before}`, '--for=delete', '--timeout=150s'], {
    timeout: 160_000,
    env: ocEnv,
  })
  let takeover = ''
  await expect.poll(() => {
    takeover = liveLeaderExcept(before)
    return takeover
  }, { timeout: 150_000, intervals: [3_000] }).toMatch(/^vault-[0-2]$/)
  expect(takeover).not.toBe(before)
  execFileSync(OC, ['-n', 'sg-vault', 'wait', `pod/${before}`, '--for=condition=Ready', '--timeout=150s'], {
    timeout: 160_000,
    env: ocEnv,
  })
  const after = takeover
  await expect(async () => {
    await page.reload()
    await expect(leaderNode).toHaveText(after, { timeout: 4_000 })
    await expect(page.locator('.live-unsealed')).toContainText('3/3 members currently verified unsealed', { timeout: 4_000 })
  }).toPass({ timeout: 150_000, intervals: [5_000] })
  await context.close()
})
