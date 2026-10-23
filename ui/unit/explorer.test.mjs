import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { explorerDeclaration } from '../shared/explorer.ts'

const read = path => readFileSync(new URL(`../../policies/${path}`, import.meta.url), 'utf8')
const ownership = read('ownership-map.json')
const boundary = read('boundary-matrix.json')
const hash = value => createHash('sha256').update(value).digest('hex')
const declaration = () => ({ schemaVersion: '1', inputDigest: 'a'.repeat(64),
  sources: { ownership: { path: 'policies/ownership-map.json', sha256: hash(ownership) }, boundary: { path: 'policies/boundary-matrix.json', sha256: hash(boundary) } },
  ownership: JSON.parse(ownership).rows, boundary: JSON.parse(boundary) })

test('explorer projects the checked-in ownership and boundary registries without extra fields', () => {
  const raw = declaration()
  raw.token = 'private-fixture'
  raw.ownership[0].payload = 'private-fixture'
  raw.boundary[0].credential = 'private-fixture'
  raw.sources.ownership.contents = 'private-fixture'
  const result = explorerDeclaration(raw)
  assert.equal(result.ownership.length, 12)
  assert.equal(result.boundary.length, 19)
  assert.equal(JSON.stringify(result).includes('private-fixture'), false)
  assert.deepEqual(result.boundary, JSON.parse(boundary))
})

test('explorer rejects malformed, duplicate, unbounded and arbitrary declarations', () => {
  for (const mutate of [
    raw => { raw.schemaVersion = '2' },
    raw => { raw.inputDigest = 'not-a-digest' },
    raw => { raw.sources.boundary.path = '/private/token' },
    raw => { raw.sources.ownership.sha256 = 'unverified' },
    raw => { raw.ownership[0].owner = 'root' },
    raw => { raw.ownership[0].runbook = 'https://untrusted.invalid' },
    raw => { raw.ownership.push(raw.ownership[0]) },
    raw => { raw.boundary.push(raw.boundary[0]) },
    raw => { raw.boundary[0].expect = 'allow:execute' },
    raw => { raw.boundary[0].token = 'user-provided-token' },
    raw => { raw.boundary[0].path = '../sys/policies' },
    raw => { raw.ownership[0].scope = 'x'.repeat(601) },
    raw => { raw.ownership = [] },
    raw => { raw.boundary = Array.from({ length: 65 }, () => raw.boundary[0]) },
  ]) {
    const raw = declaration(); mutate(raw)
    assert.equal(explorerDeclaration(raw), null, String(mutate))
  }
  for (const raw of [null, {}, [], 'value']) assert.equal(explorerDeclaration(raw), null)
})
