import test from 'node:test'
import assert from 'node:assert/strict'
import { observation } from '../shared/observation.ts'
import { capabilities } from '../shared/capabilities.ts'
import { rotationValue, validOperationId } from '../shared/rotation.ts'
import { logoutSubject } from '../shared/logout-claims.ts'
import { generateKeyPair, SignJWT, jwtVerify } from 'jose'

test('missing, malformed, future and stale observations never become fresh', () => {
  const now = Date.parse('2026-10-14T12:00:00Z')
  const valid = { schemaVersion: '1', observedAt: '2026-10-14T11:00:00Z', clusterId: 'cluster', observationId: 'snapshot' }
  assert.equal(observation(null, now).availability, 'missing')
  assert.equal(observation({}, now).availability, 'invalid')
  assert.equal(observation({ ...valid, observedAt: '2027-01-01' }, now).observedAt, null)
  assert.equal(observation(valid, now).freshness, 'stale')
  assert.equal(observation(valid, now + 1000).observedAt, valid.observedAt)
})

test('approver does not silently become mutation administrator', () => {
  assert.equal(capabilities(['sg-approver']).isAdmin, false)
  assert.equal(capabilities(['sg-approver']).isOperator, false)
  assert.equal(capabilities(['sg-operator']).isOperator, true)
  assert.equal(capabilities(['sg-auditor']).isAuditor, true)
})

test('rotation preserves unrelated fields and validates retry identifiers', () => {
  const next = rotationValue({ unrelated: 'retained' }, 'fixture', 'id', 'cleo', 'now')
  assert.equal(next.unrelated, 'retained')
  assert.equal(next.rotation_id, 'id')
  assert.equal(validOperationId('not-a-uuid'), false)
  assert.equal(validOperationId('5a82bab4-d7c8-4c93-9515-4c9ffdc8234d'), true)
})

test('signed logout requires correct audience and valid logout claims', async () => {
  const { publicKey, privateKey } = await generateKeyPair('RS256')
  const payload = { sub: 'subject', jti: 'unique', events: { 'http://schemas.openid.net/event/backchannel-logout': {} } }
  const token = await new SignJWT(payload).setProtectedHeader({ alg: 'RS256' }).setIssuer('issuer').setAudience('vault').setIssuedAt().sign(privateKey)
  const verified = await jwtVerify(token, publicKey, { issuer: 'issuer', audience: 'vault', algorithms: ['RS256'] })
  assert.equal(logoutSubject(verified.payload), 'subject')
  await assert.rejects(jwtVerify(token, publicKey, { issuer: 'issuer', audience: 'other' }))
  assert.throws(() => logoutSubject({ ...verified.payload, nonce: 'forbidden' }))
  assert.throws(() => logoutSubject({ ...verified.payload, events: {} }))
})

test('snapshot shape rejects malformed nested collections', async () => {
  const { snapshotShape } = await import('../shared/snapshot.ts')
  assert.equal(snapshotShape({ schemaVersion: '1', vault: { nodes: 'bad' } }), false)
  assert.equal(snapshotShape({ phases: [], gates: {}, digest: {} }, 'layers.json'), true)
  assert.equal(snapshotShape({ phases: 'bad', gates: {}, digest: {} }, 'layers.json'), false)
  assert.throws(() => logoutSubject({ sub: 's', jti: 'j', iat: Date.now() / 1000, events: { 'http://schemas.openid.net/event/backchannel-logout': [] } }))
})

test('complete snapshot accepted; malformed nodes cannot become healthy', async () => {
  const { snapshotShape } = await import('../shared/snapshot.ts')
  const fixture = {
    vault: { total: 1, unsealed: 1, nodes: [{ name: 'vault-0', role: 'leader', reachable: true, sealed: false }] },
    sealVault: { reachable: true, sealed: false }, sealAgent: { available: true }, engines: { count: 0, enterprise: 0 },
    operator: { staticSecrets: 0, dynamicSecrets: 0, static: [], dynamic: [], workloads: [] },
    pods: { total: 0, reachable: 0, cards: [] }, routes: [], agents: [], ansible: { convergence: {}, validate: { rows: [] } },
  }
  assert.equal(snapshotShape(fixture), true)
  assert.equal(snapshotShape({ ...fixture, vault: { ...fixture.vault, nodes: [null] } }), false)
  assert.equal(snapshotShape({ ...fixture, pods: { total: 0, reachable: 1, cards: [] } }), false)
})
