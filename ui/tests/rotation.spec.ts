// Engines › Rotation — the KV rotation add-on (ADR D17).
// Runs only while the add-on is installed (rotation-not-installed.spec.ts
// covers the other state). Vault decides every action; these tests check the
// UI hides what Vault refuses and the BFF refuses it too.
import { randomUUID } from 'node:crypto'
import https from 'node:https'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, test, type APIRequestContext } from '@playwright/test'
import { BASE, pageAs } from './auth'
import { ROOT } from './users'

const SECRET = 'api-key/demo'
const REQUEST = `${BASE}/api/v1/rotation/${SECRET}/request`

/** Host-only: the managed secret's current version and value — kept in memory, never logged. */
function managed(id: string, what: 'metadata' | 'data'): Promise<Record<string, unknown>> {
  const domain = new URL(BASE).hostname.replace(/^shiftgear\./, '')
  return new Promise((resolveIt, reject) => {
    const req = https.get(`https://vault.${domain}/v1/kv/${what}/shift-gear/rotation/${id}`, {
      ca: readFileSync(resolve(ROOT, '.secrets/tls/pub/ca.pem')),
      headers: { 'X-Vault-Token': readFileSync(resolve(ROOT, '.secrets/tokens/ansible-platform'), 'utf8').trim(), 'X-Vault-Namespace': 'shift-gear' },
      timeout: 5000,
    }, res => {
      let raw = ''
      res.on('data', c => { raw += c })
      res.on('end', () => {
        try { resolveIt(JSON.parse(raw).data) } catch { reject(new Error('vault read failed')) }
      })
    })
    req.on('error', () => reject(new Error('vault transport failed')))
  })
}
const currentVersion = async () => Number((await managed(SECRET, 'metadata')).current_version)

async function installed(request: APIRequestContext): Promise<boolean> {
  const res = await request.get(`${BASE}/api/features`)
  return res.ok() && (await res.json()).rotation === 'installed'
}

for (const user of ['cleo', 'dirk', 'ada', 'finn', 'ben'] as const) {
  test(`@kv-rotation ${user}: Rotate now follows Vault capabilities`, async ({ browser }) => {
    const { context, page } = await pageAs(browser, user)
    test.skip(!(await installed(context.request)), 'KV rotation add-on not installed')
    const allowed = user === 'cleo' || user === 'dirk'
    await page.goto('/engines/rotation')
    await expect(page.getByRole('heading', { level: 1, name: 'Rotation' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Rotation' }).first()).toBeVisible()
    const toggle = page.getByRole('button', { name: SECRET })
    await expect(toggle).toBeVisible()
    await toggle.click()
    await expect(page.getByRole('button', { name: 'Rotate now' })).toHaveCount(allowed ? 1 : 0)
    if (user === 'ben') {
      await expect(page.getByText(/does not allow you to read this secret's history|history denied by Vault/).first()).toBeVisible()
    } else {
      await expect(page.getByRole('list', { name: `Version history of ${SECRET}` })).toBeVisible()
    }
    if (!allowed) {
      const before = await currentVersion()
      const res = await context.request.post(REQUEST, { headers: { Origin: BASE }, data: { operationId: randomUUID() } })
      expect(res.status()).toBe(403)
      await page.waitForTimeout(12_000)        // longer than one controller loop
      const after = await managed(SECRET, 'metadata')
      expect(String((after.custom_metadata as Record<string, string>).rotation_request ?? '')).not.toContain(user)
      expect(Number(after.current_version)).toBeGreaterThanOrEqual(before)   // the schedule may still rotate
    }
    await context.close()
  })
}

test('@kv-rotation cleo rotates now; Vault shows a new version requested by cleo', async ({ browser }) => {
  test.setTimeout(90_000)
  const { context, page } = await pageAs(browser, 'cleo')
  test.skip(!(await installed(context.request)), 'KV rotation add-on not installed')
  await page.goto('/engines/rotation')
  await page.getByRole('button', { name: SECRET }).click()
  const before = await currentVersion()
  await page.getByLabel('Reason (optional)').fill('playwright journey')
  await page.getByRole('button', { name: 'Rotate now' }).click()
  await expect(page.getByRole('status').filter({ hasText: /Rotated: v\d+ → v\d+/ })).toBeVisible({ timeout: 60_000 })
  const meta = await managed(SECRET, 'metadata')
  const version = Number(meta.current_version)
  expect(version).toBeGreaterThan(before)
  const record = (meta.custom_metadata as Record<string, string>)[`v${version}`] ?? ''
  const requested = Object.entries(meta.custom_metadata as Record<string, string>)
    .filter(([k]) => /^v\d+$/.test(k)).map(([, v]) => v).some(v => v.includes('|request|') && v.endsWith('|cleo'))
  expect(record.length).toBeGreaterThan(0)
  expect(requested).toBe(true)
  // The value itself never reaches the browser.
  const value = String(((await managed(SECRET, 'data')).data as Record<string, string>).value)
  expect(value.length).toBeGreaterThan(20)
  expect(await page.content()).not.toContain(value)
  const api = await (await context.request.get(`${BASE}/api/v1/rotation`)).text()
  expect(api).not.toContain(value)
  await context.close()
})

test('@kv-rotation duplicate operationId is one request; anonymous and foreign origin are refused', async ({ browser, request }) => {
  const { context } = await pageAs(browser, 'dirk')
  test.skip(!(await installed(context.request)), 'KV rotation add-on not installed')
  const operationId = randomUUID()
  const first = await context.request.post(REQUEST, { headers: { Origin: BASE }, data: { operationId } })
  expect(first.status()).toBe(200)
  const again = await context.request.post(REQUEST, { headers: { Origin: BASE }, data: { operationId } })
  expect(await again.json()).toEqual(await first.json())
  expect((await request.post(REQUEST, { headers: { Origin: BASE }, data: { operationId: randomUUID() } })).status()).toBe(401)
  expect((await context.request.post(REQUEST, { headers: { Origin: 'https://untrusted.invalid' }, data: { operationId: randomUUID() } })).status()).toBe(403)
  // Names that reach the handler but are not <type>/<name> DNS labels are refused.
  // (A bare ../ or %2E%2E is normalised before routing and never reaches it.)
  for (const bad of ['api-key/demo%2F..%2F..%2Fconfig', 'API/demo']) {
    const res = await context.request.post(`${BASE}/api/v1/rotation/${bad}/request`, { headers: { Origin: BASE }, data: { operationId: randomUUID() } })
    expect(res.status()).toBe(404)
  }
  await context.close()
})
