import test from 'node:test'
import assert from 'node:assert/strict'
import {
  canRequest, canViewHistory, compliancePill, decodeRecords, duration, encodeRequest,
  isManagedSecretId, nativeKey, relative, timeline, triggerLabel,
} from '../shared/kv-rotation.ts'

test('history records decode from custom metadata and ignore everything else', () => {
  const records = decodeRecords({
    v3: 'abcdef012345|request|2026-10-28T11:16:00Z|cleo',
    v2: '99afaf153e34|time|2026-10-28T11:12:20Z|schedule',
    rotation_type: 'api-key',
    v9: 'not|enough',
    vx: 'a|b|c|d',
    v4: 'NOT-HEX-VALUE|time|t|a',
  })
  assert.deepEqual([...records.keys()].sort(), [2, 3])
  assert.equal(records.get(3).actor, 'cleo')
})

test('timeline is newest first and marks unrecorded versions honestly', () => {
  const rows = timeline({
    versions: { 1: { created_time: '2026-10-28T11:11:19Z' }, 2: { created_time: '2026-10-28T11:12:20Z' }, 3: { created_time: 'x', destroyed: true } },
    custom_metadata: { v1: '929304a12450|created|2026-10-28T11:11:19Z|controller', v2: '99afaf153e34|time|2026-10-28T11:12:20Z|schedule' },
  })
  assert.deepEqual(rows.map(r => r.version), [3, 2, 1])
  assert.equal(rows[0].recorded, false)
  assert.equal(rows[0].fingerprint, 'not recorded')
  assert.equal(rows[0].destroyed, true)
  assert.equal(rows[1].trigger, 'time')
  assert.deepEqual(timeline(null), [])
})

test('requests cannot smuggle separators', () => {
  assert.equal(encodeRequest('id', 'cl|eo', 'why\nnot|now'), 'id|cleo|whynotnow')
})

test('secret ids are <type>/<name> DNS labels only', () => {
  assert.equal(isManagedSecretId('api-key/demo'), true)
  assert.equal(isManagedSecretId('../config/app-config'), false)
  assert.equal(isManagedSecretId('api-key/demo/extra'), false)
  assert.equal(isManagedSecretId('API/demo'), false)
})

test('durations and relative times', () => {
  assert.equal(duration(45), '45s')
  assert.equal(duration(200), '3m 20s')
  assert.equal(duration(7500), '2h 5m')
  assert.equal(duration(30 * 86400), '30d')
  assert.equal(duration(null), '—')
  assert.equal(relative(100, 60_000), 'in 40s')
  assert.equal(relative(20, 60_000), '40s ago')
})

test('capabilities decide the actions, missing compliance is not a verdict', () => {
  assert.equal(canRequest(['read', 'list', 'patch']), true)
  assert.equal(canRequest(['read', 'list']), false)
  assert.equal(canRequest(['deny']), false)
  assert.equal(canViewHistory(['read']), true)
  assert.equal(canViewHistory([]), false)
  assert.equal(compliancePill(undefined).label, 'Not reported')
  assert.equal(compliancePill(false).tone, 'rejected')
  assert.equal(triggerLabel('usage'), 'After use')
  assert.equal(triggerLabel(''), 'Not recorded')
})

test('a natively rotated Transit key is read from public metadata only', () => {
  const k = nativeKey('session-signing', 200, { data: { latest_version: 3, auto_rotate_period: 3600,
    keys: { 1: { creation_time: '2026-10-29T08:00:00Z' }, 2: { creation_time: '2026-10-29T09:00:00Z' }, 3: { creation_time: '2026-10-29T10:00:00Z' } } } })
  assert.equal(k.state, 'live')
  assert.equal(k.latestVersion, 3)
  assert.equal(k.autoRotateSeconds, 3600)
  assert.equal(k.lastRotated, '2026-10-29T10:00:00.000Z')
  assert.equal(nativeKey('x', 403, null).state, 'denied')
  assert.equal(nativeKey('x', 500, null).state, 'unavailable')
  assert.equal(nativeKey('x', 200, { data: { latest_version: 1, keys: { 1: 1761724800 } } }).lastRotated, '2025-10-29T08:00:00.000Z')
})
