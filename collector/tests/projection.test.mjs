import test from 'node:test'
import assert from 'node:assert/strict'
import { parse } from '../projection.mjs'

test('audit projection excludes arbitrary request, response and authentication values', () => {
  const canary = 'fixture-sensitive-value'
  const row = parse(JSON.stringify({ request: { path: 'kv/data/example', operation: 'read', data: { token: canary } },
    auth: { client_token: canary, display_name: 'fixture', policies: ['default'] }, response: { data: { password: canary, protected: 'hmac-sha256:fixture' } } }))
  assert.equal(JSON.stringify(row).includes(canary), false)
  assert.equal(row.path, 'kv/data/example')
  assert.deepEqual(row.hmacFields, ['response.data.protected'])
  assert.equal(parse('{invalid'), null)
  assert.equal(parse('{}'), null)
})

test('deep nested metadata cannot overflow collector recursion', () => {
  const data = {}; let cursor = data
  for (let i = 0; i < 200; i++) { cursor.next = {}; cursor = cursor.next }
  assert.doesNotThrow(() => parse(JSON.stringify({ request: { data } })))
})

test('stored metadata fields and policy lists remain bounded', () => {
  const row = parse(JSON.stringify({ request: { path: 'x'.repeat(5000) }, auth: { policies: Array(100).fill('policy') }, error: 'e'.repeat(2000) }))
  assert.equal(row.path.length, 2048)
  assert.equal(row.error.length, 512)
  assert.equal(row.policies.length, 64)
})
