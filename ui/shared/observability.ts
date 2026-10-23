export const METRICS = ['up', 'sg_audit_received_total', 'sg_audit_ring_dropped_total', 'sg_audit_malformed_total',
  'sg_audit_connections', 'sg_audit_ring_entries', 'sg_audit_listener_up', 'sg_audit_archive_up',
  'sg_audit_archive_committed_total', 'sg_audit_archive_failed_total', 'sg_audit_archive_queue_dropped_total',
  'sg_audit_archive_retained_entries', 'sg_audit_archive_bytes', 'sg_audit_archive_pruned_total', 'sg_audit_archive_corrupt_total'] as const
export interface MetricSample { name: string; value: number; at: string }
export interface RetainedEntry { id: string; retainedAt: string; time: string | null; type: string | null; operation: string | null; namespace: string | null; path: string | null; hasError: boolean }
export interface ArchiveStatus { available: boolean; committed: number; failed: number; queueDropped: number; corrupt: number; pruned: number; bytes: number; retained: number; queued: number; maxBytes: number; retentionSeconds: number; oldestAt: string | null; lastCommittedAt: string | null }
export interface ObservabilityResponse {
  checkedAt: string
  metrics: { backend: 'none' | 'opentelemetry' | 'prometheus'; state: 'disabled' | 'available' | 'unavailable' | 'invalid'; samples: MetricSample[] }
  archive: { state: 'disabled' | 'available' | 'unavailable' | 'invalid'; status: ArchiveStatus | null; entries: RetainedEntry[] }
}
const record = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const number = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v) && v >= 0
const text = (v: unknown, length = 2048): v is string => typeof v === 'string' && v.length <= length
const time = (v: unknown): v is string => typeof v === 'string' && Number.isFinite(Date.parse(v))
export function metricSamples(raw: unknown): MetricSample[] | null {
  if (!record(raw) || raw.status !== 'success' || !record(raw.data) || raw.data.resultType !== 'matrix' || !Array.isArray(raw.data.result) || raw.data.result.length > METRICS.length) return null
  const samples: MetricSample[] = []
  for (const item of raw.data.result) {
    if (!record(item) || !record(item.metric) || !METRICS.includes(item.metric.__name__ as typeof METRICS[number])
      || !Array.isArray(item.values) || item.values.length > 12 || !item.values.length) return null
    const last = item.values.at(-1)
    if (!Array.isArray(last) || last.length !== 2 || !number(last[0]) || typeof last[1] !== 'string' || !last[1].length || !number(Number(last[1]))) return null
    if (!Number.isFinite(new Date(last[0] * 1000).getTime()) || !/^\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$/.test(last[1])) return null
    samples.push({ name: String(item.metric.__name__), value: Number(last[1]), at: new Date(last[0] * 1000).toISOString() })
  }
  return new Set(samples.map(row => row.name)).size === samples.length ? samples : null
}
export function archiveObservation(raw: unknown): { status: ArchiveStatus; entries: RetainedEntry[] } | null {
  if (!record(raw) || !record(raw.archive) || !Array.isArray(raw.entries) || raw.entries.length > 200) return null
  const a = raw.archive
  const keys = ['committed', 'failed', 'queueDropped', 'corrupt', 'pruned', 'bytes', 'retained', 'queued', 'maxBytes', 'retentionSeconds'] as const
  if (typeof a.available !== 'boolean' || !keys.every(key => number(a[key]) && Number.isSafeInteger(a[key])) || !(a.oldestAt === null || time(a.oldestAt)) || !(a.lastCommittedAt === null || time(a.lastCommittedAt))) return null
  const entries: RetainedEntry[] = []
  for (const row of raw.entries) {
    if (!record(row) || !text(row.id, 96) || !time(row.retainedAt) || typeof row.hasError !== 'boolean'
      || !['time', 'type', 'operation', 'namespace', 'path'].every(key => row[key] === null || text(row[key]))) return null
    entries.push({ id: row.id, retainedAt: row.retainedAt, time: row.time as string | null, type: row.type as string | null,
      operation: row.operation as string | null, namespace: row.namespace as string | null, path: row.path as string | null, hasError: row.hasError })
  }
  const status = Object.fromEntries(keys.map(key => [key, a[key]])) as unknown as ArchiveStatus
  return { status: { ...status, available: a.available, oldestAt: a.oldestAt, lastCommittedAt: a.lastCommittedAt }, entries }
}

// OpenTelemetry's private exporter includes actual underlying scrape timestamps.
// Project only known numeric metrics, dropping all labels and unrelated series.
export function exportedMetricSamples(raw: unknown): MetricSample[] | null {
  if (typeof raw !== 'string' || raw.length > 1024 * 1024) return null
  const samples: MetricSample[] = []
  for (const line of raw.split('\n')) {
    if (!line || line.startsWith('#')) continue
    const name = /^([a-zA-Z_:][a-zA-Z0-9_:]*)/.exec(line)?.[1]
    if (!METRICS.includes(name as typeof METRICS[number])) continue
    const match = /^([a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{[^\n]{0,1024}\})? ([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?) ([0-9]+)$/.exec(line)
    if (!match || !number(Number(match[2])) || !number(Number(match[3])) || !Number.isFinite(new Date(Number(match[3])).getTime())) return null
    samples.push({ name: match[1]!, value: Number(match[2]), at: new Date(Number(match[3])).toISOString() })
  }
  return samples.length && new Set(samples.map(row => row.name)).size === samples.length ? samples : null
}
