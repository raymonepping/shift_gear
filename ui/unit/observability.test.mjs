import test from 'node:test'
import assert from 'node:assert/strict'
import { metricSamples, exportedMetricSamples, archiveObservation } from '../shared/observability.ts'

const matrix = () => ({ status: 'success', data: { resultType: 'matrix', result: [{ metric: { __name__: 'sg_audit_received_total', job: 'sg-audit', private: 'private-fixture' }, values: [[1234, '12']] }] } })
test('metric projection preserves actual scrape time and never forwards arbitrary series or labels', () => {
  assert.deepEqual(metricSamples(matrix()), [{ name: 'sg_audit_received_total', value: 12, at: '1970-01-01T00:20:34.000Z' }])
  for (const value of ['NaN', 'Infinity', ' ', '-3']) { const raw = matrix(); raw.data.result[0].values[0][1] = value; assert.equal(metricSamples(raw), null) }
  const bad = matrix(); bad.data.result[0].metric.__name__ = 'private-fixture'; assert.equal(metricSamples(bad), null)
  const huge = matrix(); huge.data.result[0].values[0][0] = 1e308; assert.equal(metricSamples(huge), null)
  const duplicate = matrix(); duplicate.data.result.push(duplicate.data.result[0]); assert.equal(metricSamples(duplicate), null)
})

test('retained metadata excludes credentials, actor and raw error fields even from disk responses', () => {
  const raw = { archive: { available: true, committed: 1, failed: 0, queueDropped: 0, corrupt: 0, pruned: 0, bytes: 300, retained: 1, queued: 0, maxBytes: 67108864, retentionSeconds: 604800, oldestAt: null, lastCommittedAt: null, password: 'private-fixture' },
    entries: [{ id: 'fixture:1', retainedAt: '2026-10-22T00:00:00Z', time: null, type: 'request', operation: 'read', namespace: 'shift-gear/', path: 'kv/example', hasError: true, error: 'private-fixture', actor: 'private-fixture', auth: { token: 'private-fixture' } }] }
  assert.equal(JSON.stringify(archiveObservation(raw)).includes('private-fixture'), false)
  assert.equal(archiveObservation(raw).entries[0].hasError, true)
  assert.equal(archiveObservation({ ...raw, entries: Array(201).fill(raw.entries[0]) }), null)
  assert.equal(archiveObservation({ ...raw, archive: { ...raw.archive, retained: '1' } }), null)
  assert.equal(archiveObservation({ ...raw, entries: [{ ...raw.entries[0], retainedAt: 'invented' }] }), null)
  assert.equal(archiveObservation(null), null)
})

test('OpenTelemetry export retains source timestamps, excludes labels and rejects missing time or duplicates', () => {
  const row = 'sg_audit_received_total{job="sg-audit",private="fixture"} 3 1792663200123'
  assert.deepEqual(exportedMetricSamples(row), [{ name: 'sg_audit_received_total', value: 3, at: new Date(1792663200123).toISOString() }])
  assert.equal(exportedMetricSamples(row + '\n' + row), null)
  assert.equal(exportedMetricSamples('sg_audit_received_total 3'), null)
  assert.equal(exportedMetricSamples('sg_audit_received_total NaN 1792663200123'), null)
  assert.equal(exportedMetricSamples('sg_audit_received_total 3 99999999999999999999'), null)
  assert.deepEqual(exportedMetricSamples('other_identity 2\n' + row), exportedMetricSamples(row))
})
