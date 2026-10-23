import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, rm, readdir, readFile, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { MetadataArchive } from '../archive.mjs'
import { metrics } from '../metrics.mjs'

async function fixture(run) { const dir = await mkdtemp(join(tmpdir(), 'sg-archive-')); try { await run(dir) } finally { await rm(dir, { recursive: true, force: true }) } }
const row = (n = 1) => ({ id: `fixture:${n}`, time: '2026-10-22T00:00:00Z', type: 'request', operation: 'read', namespace: 'shift-gear/', path: 'kv/data/example', error: 'private-fixture-error', auth: { token: 'private-fixture-token' }, displayName: 'private-fixture-person', policies: ['private-fixture-policy'], response: { password: 'private-fixture-password' } })

test('archive commits fixed metadata and recovers original observation identity after restart', async () => fixture(async dir => {
  const archive = new MetadataArchive(dir); await archive.init(); archive.append(row()); await archive.close()
  const disk = (await Promise.all((await readdir(dir)).map(name => readFile(join(dir, name), 'utf8')))).join('')
  assert.equal(disk.includes('private-fixture'), false)
  const restored = new MetadataArchive(dir); await restored.init()
  const rows = await restored.newest()
  assert.equal(rows.length, 1); assert.equal(rows[0].id, 'fixture:1'); assert.equal(rows[0].hasError, true)
  assert.equal(restored.status().retained, 1); assert.equal(restored.status().available, true)
  await restored.close()
}))

test('archive enforces age and byte budgets without deleting unrelated files', async () => fixture(async dir => {
  let now = Date.now()
  const archive = new MetadataArchive(dir, { maxBytes: 4096, segmentBytes: 1024, retentionMs: 1000, clock: () => now })
  await archive.init(); await writeFile(join(dir, 'operator-note.txt'), 'preserve')
  for (let n = 0; n < 60; n++) archive.append({ ...row(n), path: 'x'.repeat(400) })
  await archive.worker
  assert.ok(archive.status().bytes <= 4096); assert.ok(archive.status().pruned > 0)
  now += 1001; archive.maintain(); await archive.worker
  assert.equal((await archive.newest()).length, 0); assert.equal(archive.status().bytes, 0)
  assert.equal(await readFile(join(dir, 'operator-note.txt'), 'utf8'), 'preserve')
  await archive.close()
}))

test('archive reports unavailable storage and bounded queue drops without throwing into ingest', async () => fixture(async dir => {
  const file = join(dir, 'not-a-directory'); await writeFile(file, 'preserve')
  const archive = new MetadataArchive(file); await archive.init()
  assert.equal(archive.status().available, false)
  assert.doesNotThrow(() => archive.append(row())); await archive.worker
  assert.ok(archive.status().failed > 0); await archive.close()
  const bounded = new MetadataArchive(join(dir, 'bounded'), { queueBytes: 1 })
  await bounded.init(); assert.equal(bounded.append(row()), false); assert.equal(bounded.status().queueDropped, 1); await bounded.close()
}))

test('archive ignores partial crash tails and does not append new records into them', async () => fixture(async dir => {
  const archive = new MetadataArchive(dir); await archive.init(); archive.append(row()); await archive.close()
  const name = (await readdir(dir))[0]
  await writeFile(join(dir, name), (await readFile(join(dir, name), 'utf8')) + '{partial')
  const recovered = new MetadataArchive(dir); await recovered.init(); recovered.append(row(2)); await recovered.worker
  assert.deepEqual((await recovered.newest()).map(row => row.id), ['fixture:2', 'fixture:1'])
  assert.equal(recovered.status().corrupt, 1); await recovered.close()
}))

test('metrics contain numeric fixed series and no audit identity or path labels', () => {
  const body = metrics({ received: 3, dropped: 1, malformed: 0, connections: 1, stored: 2, listening: true, path: 'private-fixture' }, { available: true, committed: 3, failed: 0, queueDropped: 0, retained: 3, bytes: 600, pruned: 0, corrupt: 0 })
  assert.equal(body.includes('private-fixture'), false); assert.equal(body.includes('{'), false)
  assert.match(body, /sg_audit_archive_up 1\n/)
  for (const line of body.split('\n').filter(line => line && !line.startsWith('#'))) assert.match(line, /^sg_audit_[a-z_]+ [0-9]+$/)
})
