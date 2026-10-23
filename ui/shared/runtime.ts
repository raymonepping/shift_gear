export interface RuntimeSource {
  name: string
  owner: string
  resource: string
  state: 'available' | 'unavailable' | 'denied' | 'invalid'
  reason?: 'timeout' | 'too-large' | 'tls' | 'connection' | 'configuration' | 'http' | 'access-denied' | 'schema'
  observedAt: string | null
  checkedAt: string
  data: Record<string, string | number | boolean | null>
}

export interface RuntimeResponse { sources: RuntimeSource[] }

/** Never pass an upstream response or error body through to the browser. */
export function runtimeSource(name: string, owner: string, resource: string, status: number,
  raw: unknown, project: (value: Record<string, unknown>) => RuntimeSource['data'], now = Date.now(), failureReason: RuntimeSource['reason'] = 'connection'): RuntimeSource {
  const checkedAt = new Date(now).toISOString()
  const base = { name, owner, resource, checkedAt, observedAt: null, data: {} }
  if (status === 401 || status === 403) return { ...base, state: 'denied', reason: 'access-denied' }
  if (status < 200 || status >= 300) return { ...base, state: 'unavailable', reason: status === 0 ? failureReason : 'http' }
  try {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('shape')
    const data = project(raw as Record<string, unknown>)
    return { ...base, state: 'available', observedAt: checkedAt, data }
  } catch { return { ...base, state: 'invalid', reason: 'schema' } }
}
