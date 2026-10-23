import test from 'node:test'
import assert from 'node:assert/strict'
import { runtimeSource } from '../shared/runtime.ts'

const project = raw => {
  if (typeof raw.ready !== 'boolean') throw new Error('malformed')
  return { ready: raw.ready }
}
const probe = (status, raw, now = 0) => runtimeSource('Vault', 'Vault', 'fixed-resource', status, raw, project, now)

test('runtime outage, denial and invalid bodies cannot become observations', () => {
  for (const [status, raw, state] of [[0, null, 'unavailable'], [503, { ready: true }, 'unavailable'], [403, { token: 'fixture' }, 'denied'], [200, {}, 'invalid'], [200, [], 'invalid']]) {
    const result = probe(status, raw)
    assert.equal(result.state, state)
    assert.equal(result.observedAt, null)
    assert.deepEqual(result.data, {})
  }
})
test('runtime sources are independent and return only projected metadata', () => {
  const good = probe(200, { ready: true, private_key: 'fixture-private-value' })
  assert.deepEqual(good.data, { ready: true })
  assert.equal(good.observedAt, '1970-01-01T00:00:00.000Z')
  const failed = probe(503, {})
  assert.equal(failed.state, 'unavailable')
  assert.equal(good.state, 'available')
  assert.equal(probe(200, { ready: true }, 1000).observedAt, '1970-01-01T00:00:01.000Z')
})

test('published component receipts reject invalid count, source digest and future time', async () => {
  const { proofShape } = await import('../shared/snapshot.ts')
  const valid = { result: 'pass', at: new Date().toISOString(), inputDigest: 'a'.repeat(64), passedChecks: 18, scope: 'dedicated-fixtures', expiryFixtureSeconds: 5 }
  assert.equal(proofShape(valid), true)
  for (const bad of [{ passedChecks: 0 }, { passedChecks: '18' }, { inputDigest: 'arbitrary' }, { at: new Date(Date.now() + 86400000).toISOString() }, { scope: 'production' }]) assert.equal(proofShape({ ...valid, ...bad }), false)
})


test('runtime transport failures distinguish timeout, trust, denial and invalid data', () => {
  const timeout = runtimeSource('Vault', 'Vault', 'fixed', 0, null, project, 0, 'timeout')
  assert.equal(timeout.reason, 'timeout')
  assert.equal(timeout.observedAt, null)
  assert.equal(runtimeSource('Identity', 'Ansible', 'fixed', 0, null, project, 0, 'tls').reason, 'tls')
  assert.equal(probe(403, {}).reason, 'access-denied')
  assert.equal(probe(200, {}).reason, 'schema')
})
