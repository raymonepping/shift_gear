import { requireSession } from '../../utils/session'
import { archiveObservation, metricSamples, exportedMetricSamples, type ObservabilityResponse } from '../../../shared/observability'

async function bounded(url: string, format: 'json' | 'text' = 'json'): Promise<unknown> {
  // URLs are fixed below; no browser URL, path, query or credential is accepted.
  const response = await fetch(url, { signal: AbortSignal.timeout(3000), redirect: 'error' })
  if (!response.ok || !response.body) throw new Error('upstream unavailable')
  const reader = response.body.getReader(); const chunks: Uint8Array[] = []; let bytes = 0
  try {
    while (true) {
      const chunk = await reader.read()
      if (chunk.done) break
      bytes += chunk.value.byteLength
      if (bytes > 1024 * 1024) throw new Error('response limit')
      chunks.push(chunk.value)
    }
    const text = Buffer.concat(chunks).toString('utf8')
    return format === 'json' ? JSON.parse(text) : text
  } finally { await reader.cancel().catch(() => {}) }
}
export default defineEventHandler(async (event): Promise<ObservabilityResponse> => {
  await requireSession(event)
  if (!['GET', 'HEAD'].includes(event.method)) {
    setResponseHeader(event, 'Allow', 'GET, HEAD')
    throw createError({ statusCode: 405, statusMessage: 'Observations are read only' })
  }
  if (Object.keys(getQuery(event)).length) throw createError({ statusCode: 400, statusMessage: 'No query parameters accepted' })
  const config = useRuntimeConfig()
  const backend = ['none', 'opentelemetry', 'prometheus'].includes(config.metricsBackend) ? config.metricsBackend as 'none' | 'opentelemetry' | 'prometheus' : 'none'
  const archiveEnabled = String(config.auditArchiveEnabled) === 'true'
  const query = encodeURIComponent('{__name__=~"up|sg_audit_.*",job="sg-audit"}[1m]')
  const [metricResult, archiveResult] = await Promise.allSettled([
    backend === 'none' ? Promise.resolve(null) : backend === 'opentelemetry'
      ? bounded('http://sg-otel.sg-app.svc:9090/metrics', 'text')
      : bounded(`http://sg-metrics.sg-app.svc:9090/api/v1/query?query=${query}`),
    archiveEnabled ? bounded('http://sg-audit.sg-app.svc:8080/archive') : Promise.resolve(null),
  ])
  const metrics = metricResult.status === 'fulfilled' ? (backend === 'opentelemetry' ? exportedMetricSamples(metricResult.value) : metricSamples(metricResult.value)) : null
  const archive = archiveResult.status === 'fulfilled' ? archiveObservation(archiveResult.value) : null
  return {
    checkedAt: new Date().toISOString(),
    metrics: { backend, state: backend === 'none' ? 'disabled' : metrics ? 'available' : metricResult.status === 'rejected' ? 'unavailable' : 'invalid', samples: metrics ?? [] },
    archive: { state: !archiveEnabled ? 'disabled' : archive ? 'available' : archiveResult.status === 'rejected' ? 'unavailable' : 'invalid', status: archive?.status ?? null, entries: archive?.entries ?? [] },
  }
})
