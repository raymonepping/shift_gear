// server/utils/rotation.ts — the KV rotation add-on (ADR D17) as seen by the BFF.
//
// The add-on is optional. Its controller serves read-only, non-secret JSON
// (/healthz /status /compliance) on a cluster-internal Service that only the
// sg-ui pods may reach (NetworkPolicy). Everything a person *does* goes to
// Vault with their own token, so Vault decides; the controller is never asked
// to act on a browser's behalf.
import http from 'node:http'
import type { RotationFeature } from '../../shared/kv-rotation'

export interface ControllerReply { feature: RotationFeature; status: number; json: unknown; reason?: string }

function get(path: string, timeoutMs = 1500): Promise<ControllerReply> {
  const base = useRuntimeConfig().rotationControllerBase as string
  return new Promise((resolve) => {
    let url: URL
    try {
      url = new URL(path, base)
    } catch {
      resolve({ feature: 'not-installed', status: 0, json: null, reason: 'not configured' })
      return
    }
    const req = http.get(url, { timeout: timeoutMs }, (res) => {
      let raw = ''
      res.setEncoding('utf8')
      res.on('data', (c) => { if (raw.length < 2_000_000) raw += c })
      res.on('end', () => {
        let json: unknown
        try { json = raw ? JSON.parse(raw) : null } catch { json = null }
        const ok = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300
        resolve({ feature: ok ? 'installed' : 'degraded', status: res.statusCode ?? 0, json })
      })
    })
    req.on('timeout', () => req.destroy(Object.assign(new Error('timeout'), { code: 'ETIMEDOUT' })))
    req.on('error', (err: NodeJS.ErrnoException) => {
      // No Service name at all = the add-on is not installed. A Service that
      // does not answer = installed but not healthy.
      const absent = err.code === 'ENOTFOUND' || err.code === 'EAI_AGAIN'
      resolve({ feature: absent ? 'not-installed' : 'degraded', status: 0, json: null, reason: err.code ?? 'error' })
    })
  })
}

let cached: { at: number; value: ControllerReply } | null = null

/** Installed / degraded / not installed, cached for 15 s. */
export async function rotationFeature(): Promise<ControllerReply> {
  if (cached && Date.now() - cached.at < 15_000) return cached.value
  const value = await get('/healthz')
  cached = { at: Date.now(), value }
  return value
}

export function controllerGet(path: '/status' | '/compliance'): Promise<ControllerReply> {
  return get(path, 3000)
}
