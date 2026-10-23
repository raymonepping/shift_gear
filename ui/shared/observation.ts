export interface Observation {
  schemaVersion: '1'
  source: 'snapshot'
  observedAt: string | null
  retrievedAt: string
  availability: 'available' | 'missing' | 'invalid'
  freshness: 'fresh' | 'stale' | 'unknown'
  clusterId: string | null
  runId: string | null
  observationId: string | null
}

export function observation(raw: unknown, now = Date.now(), maxAgeSeconds = 120): Observation {
  const obj = raw && typeof raw === 'object' ? raw as Record<string, unknown> : null
  const timestamp = obj?.observedAt ?? obj?.generated_at
  const time = typeof timestamp === 'string' ? Date.parse(timestamp) : NaN
  const valid = obj?.schemaVersion === '1' && Number.isFinite(time) && time <= now + 5000
    && typeof obj?.clusterId === 'string' && typeof obj?.observationId === 'string'
  return {
    schemaVersion: '1', source: 'snapshot',
    observedAt: valid ? timestamp as string : null,
    retrievedAt: new Date(now).toISOString(),
    availability: !obj ? 'missing' : valid ? 'available' : 'invalid',
    freshness: !valid ? 'unknown' : now - time > maxAgeSeconds * 1000 ? 'stale' : 'fresh',
    clusterId: valid ? obj!.clusterId as string : null,
    runId: valid && typeof obj!.runId === 'string' ? obj!.runId : null,
    observationId: valid ? obj!.observationId as string : null,
  }
}
