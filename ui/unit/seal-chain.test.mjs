import test from 'node:test'
import assert from 'node:assert/strict'
import { projectVaultHealth, projectSealAgent, sealSourceNames, sealChainStatus, vaultHealthStatus } from '../shared/seal-chain.ts'
import { runtimeSource } from '../shared/runtime.ts'

const now = Date.parse('2026-10-23T08:00:00Z')
const health = { initialized: true, sealed: false, standby: false, performance_standby: false }
function fixture(at = now) {
  return sealSourceNames.map((name, index) => ({ name, owner: 'fixture', resource: 'fixed', state: 'available',
    observedAt: new Date(at).toISOString(), checkedAt: new Date(at).toISOString(),
    data: index === 1 ? { available: true } : projectVaultHealth({ ...health, standby: index > 2 }) }))
}

test('all five live observations are required; snapshots and unrelated sources cannot turn the chain green', () => {
  assert.equal(sealChainStatus(fixture(), now).tone, 'healthy')
  assert.equal(sealChainStatus(fixture(), now).label, 'Seal chain 3/3')
  for (let i = 0; i < 5; i++) {
    const sources = fixture()
    sources.splice(i, 1)
    assert.equal(sealChainStatus(sources, now).tone, 'unknown')
  }
  assert.equal(sealChainStatus([], now).tone, 'unknown')
  const sources = fixture()
  sources.push({ ...sources[0], name: 'Identity discovery', state: 'unavailable' })
  assert.equal(sealChainStatus(sources, now).tone, 'healthy')
})

test('staleness, future times, malformed times and failed refreshes withdraw the healthy label', () => {
  assert.equal(sealChainStatus(fixture(now - 30000), now).tone, 'healthy')
  assert.equal(sealChainStatus(fixture(now - 30001), now).tone, 'unknown')
  assert.equal(sealChainStatus(fixture(now + 5001), now).tone, 'unknown')
  assert.equal(sealChainStatus(fixture(), now, true).tone, 'unknown')
  for (const state of ['unavailable', 'denied', 'invalid']) {
    const sources = fixture(); sources[2].state = state
    assert.equal(sealChainStatus(sources, now).tone, 'unknown')
  }
  const sources = fixture(); sources[0].observedAt = 'invalid'
  assert.equal(sealChainStatus(sources, now).tone, 'unknown')
})

test('sealed, uninitialized, Agent failure and inconsistent leadership cannot report healthy', () => {
  for (const index of [0, 2, 3, 4]) {
    const sources = fixture(); sources[index].data.sealed = true
    assert.equal(sealChainStatus(sources, now).tone, 'critical')
  }
  const agent = fixture(); agent[1].data.available = false
  assert.equal(sealChainStatus(agent, now).label, 'Seal Agent unavailable')
  const uninitialized = fixture(); uninitialized[0].data.initialized = false
  assert.equal(sealChainStatus(uninitialized, now).tone, 'critical')
  const members = fixture(); members[4].data.initialized = false
  assert.equal(sealChainStatus(members, now).tone, 'degraded')
  const leaders = fixture(); leaders[3].data.standby = false
  assert.equal(sealChainStatus(leaders, now).tone, 'degraded')
  const partial = fixture(); partial[0].state = 'unavailable'; partial[2].data.sealed = true
  assert.equal(sealChainStatus(partial, now).label, 'Vault member sealed')
})

test('real Vault health codes preserve negative observations and never expose arbitrary payload fields', () => {
  for (const status of [200, 429, 472, 473, 501, 503]) {
    const source = runtimeSource('Vault', 'Vault', 'fixed', vaultHealthStatus(status), { ...health, sealed: true, secret: 'discard' }, projectVaultHealth, now)
    assert.equal(source.state, 'available')
    assert.equal(source.data.sealed, true)
    assert.equal(source.data.secret, undefined)
  }
  for (const status of [0, 302, 401, 403, 500, 502, 504]) {
    assert.notEqual(runtimeSource('Vault', 'Vault', 'fixed', vaultHealthStatus(status), health, projectVaultHealth, now).state, 'available')
  }
  for (const missing of Object.keys(health)) {
    const value = { ...health }; delete value[missing]
    assert.throws(() => projectVaultHealth(value))
  }
})

test('Agent readiness requires the current generation and desired updated replicas', () => {
  const raw = { metadata: { name: 'seal-agent', generation: 4 }, spec: { replicas: 1 }, status: { observedGeneration: 4, availableReplicas: 1, updatedReplicas: 1 }, secret: 'discard' }
  assert.deepEqual(projectSealAgent(raw), { available: true })
  for (const status of [{ observedGeneration: 3, availableReplicas: 1, updatedReplicas: 1 }, { observedGeneration: 4 }, { observedGeneration: 4, availableReplicas: 1, updatedReplicas: 0 }]) {
    assert.equal(projectSealAgent({ ...raw, status }).available, false)
  }
  for (const bad of [{ metadata: { name: 'unrelated' } }, { status: { observedGeneration: 4, availableReplicas: '1' } }, { spec: { replicas: 0 } }]) {
    assert.throws(() => projectSealAgent({ ...raw, ...bad }))
  }
})
