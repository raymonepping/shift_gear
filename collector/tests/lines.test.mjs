import test from 'node:test'
import assert from 'node:assert/strict'
import { lineDecoder } from '../lines.mjs'

test('oversize complete and fragmented lines are dropped before parsing', () => {
  const rows = []
  let bad = 0
  const consume = lineDecoder(line => rows.push(line), () => bad++, 8)
  consume('123456789\nokay\n')
  consume('123456')
  consume('789tail\ngood\n')
  assert.equal(bad, 2)
  assert.deepEqual(rows, ['okay', 'good'])
})

test('bound is bytes rather than characters', () => {
  const rows = []
  let bad = 0
  const consume = lineDecoder(line => rows.push(line), () => bad++, 3)
  consume('éé\na\n')
  assert.equal(bad, 1)
  assert.deepEqual(rows, ['a'])
})
