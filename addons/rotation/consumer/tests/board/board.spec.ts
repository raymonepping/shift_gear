// d04 — the Secure Door board against the live verifier and client (prompts 01_09, 01_10).
import AxeBuilder from '@axe-core/playwright'
import { expect, test } from '@playwright/test'
import { execFileSync } from 'node:child_process'
import https from 'node:https'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const ROOT = resolve(__dirname, '../../../../..')
const domain = new URL(process.env.SG_BOARD_URL!).hostname.replace(/^secure-door\./, '')

function vault(kind: 'metadata' | 'data'): Promise<any> {
  return new Promise((ok, fail) => {
    https.get(`https://vault.${domain}/v1/kv/${kind}/shift-gear/rotation/api-key/secure-door`, {
      ca: readFileSync(resolve(ROOT, '.secrets/tls/pub/ca.pem')),
      headers: { 'X-Vault-Token': readFileSync(resolve(ROOT, '.secrets/tokens/ansible-platform'), 'utf8').trim(), 'X-Vault-Namespace': 'shift-gear' },
    }, (res) => { let raw = ''; res.on('data', (c) => { raw += c }); res.on('end', () => ok(JSON.parse(raw).data)) }).on('error', fail)
  })
}

test('the hero, both lanes and the mode match Vault and the honesty statement', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(/ACCESS GRANTED|ACCESS DENIED|STALE/, { timeout: 20_000 })
  const current = (await vault('metadata')).current_version
  const near = new RegExp(`^v(${current}|${current - 1}|${current + 1})$`)
  await expect(page.locator('#door-client-version')).toHaveText(near, { timeout: 15_000 })
  await expect(page.locator('#door-verifier-version')).toHaveText(near)
  await expect(page.locator('#door-mode')).toHaveText(/^(grace \d+ s|strict)$/)
  await expect(page.getByText(/The door is fictional; the trust decision is real:/)).toBeVisible()
  await expect(page.getByText(/a separate verifier, with its own\s+identity and its own copy of the secret, accepts the new key and rejects the old one/)).toBeVisible()
  await expect(page.locator('body')).not.toContainText(/agent healthy/i)
  for (const party of ['verifier', 'client']) {
    await expect(page.locator(`#${party}-answering`)).toHaveText('answering')
    // Baseline: Vault is reachable from each pod (a broken probe must fail here, not pass).
    await expect(page.locator(`#${party}-vault`)).toContainText(/^reachable · unsealed/, { timeout: 20_000 })
    await expect(page.locator(`#${party}-credential`)).toContainText('state current')
  }
  await expect(page.locator('#verifier-ring li').first()).toContainText(/v\d+/)
  // d02–d03b ran strict rotations, replayed an old key and a nonce, and cut the client off
  // past the grace period: the windows and refusals are on the board.
  await expect(page.locator('#window-rows tr').first()).toContainText('version-retired')
  await expect(page.locator('#verdict-counts')).toContainText(/denied · version-retired/)
  await expect(page.locator('#verdict-counts')).toContainText(/denied · replayed-nonce/)
  await expect(page.locator('#verdict-counts')).toContainText(/denied · stale-timestamp/)
  // A client-first rotation ends in a version-unknown refusal (then the fallback is granted).
  await expect(page.locator('#last-refusal')).toContainText(/Last refused request: .*(version-retired|version-unknown|replayed-nonce|stale-timestamp)/)
})

test('a rotation reaches the board, and no value ever does', async ({ page, request }) => {
  await page.goto('/')
  await expect(page.locator('#conn')).toHaveText('live', { timeout: 20_000 })
  const before = (await vault('metadata')).current_version
  execFileSync('make', ['rotation-rotate', 'SECRET=api-key/secure-door', 'REASON=board journey'], { cwd: ROOT, stdio: 'ignore' })
  const t0 = Date.now()
  await expect(page.locator('#timeline li').first()).toContainText(new RegExp(`v\\d+ → v(${before + 1}|${before + 2})`), { timeout: 30_000 })
  const shownAfterMs = Date.now() - t0
  test.info().annotations.push({ type: 'rotation-to-board-ms', description: String(shownAfterMs) })
  const value = (await vault('data')).data.value as string
  expect(value.length).toBeGreaterThan(20)
  expect(await page.content()).not.toContain(value)
  expect(await (await request.get('/api/state')).text()).not.toContain(value)
})

test('axe WCAG 2.1 AA: 0 violations (with reduced motion too)', async ({ page }) => {
  for (const motion of ['no-preference', 'reduce'] as const) {
    await page.emulateMedia({ reducedMotion: motion })
    await page.goto('/')
    await expect(page.getByRole('heading', { level: 1 })).not.toHaveText('Waiting for the parties…', { timeout: 20_000 })
    const { violations } = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']).analyze()
    expect(violations.map((v) => `${motion} [${v.id}] ${v.nodes[0]?.target.join(' ')}`)).toEqual([])
  }
})

test('@screens board screenshots', async ({ page }, info) => {
  await page.goto('/')
  await expect(page.locator('#conn')).toHaveText('live', { timeout: 20_000 })
  await page.waitForTimeout(1500)
  await page.screenshot({ path: resolve(ROOT, `docs/screenshots/secure-door-${info.project.name}.png`), fullPage: true })
})
