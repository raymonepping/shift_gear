// GET /api/v1/rotation — Engines › Rotation (the KV rotation add-on, ADR D17).
//
// History comes from Vault, read with the signed-in person's own token, so it
// is shown even when the add-on is removed (history stays in Vault). Status and
// compliance come from the controller when it is installed. What the person
// may do is decided by Vault: one batched sys/capabilities-self call.
import { requireSession } from '../../utils/session'
import { vaultCall } from '../../utils/vault'
import { controllerGet, rotationFeature } from '../../utils/rotation'
import { canRequest, canViewHistory, nativeKey, timeline } from '../../../shared/kv-rotation'
import type { RotationResponse, RotationSecretView } from '../../../shared/kv-rotation'

// Keys Vault rotates natively, shown beside the KV secrets (prompt 01_10).
const NATIVE_TRANSIT_KEYS = ['session-signing']

interface ControllerStatus {
  controller: Record<string, unknown>
  config: { mount: string; prefix: string; types: Record<string, unknown>; secrets: Array<{ id: string; type: string; owner?: string; strategies: string[]; interval_seconds: number; max_reads: number | null; events: Array<{ match: string; path: string }> }> }
  secrets: Array<Record<string, unknown> & { secret: string }>
}
interface ComplianceReport { summary: Record<string, unknown>; secrets: Array<Record<string, unknown> & { secret: string }> }

const DEFAULT_MOUNT = 'kv'
const DEFAULT_PREFIX = 'shift-gear/rotation'

async function discover(token: string, mount: string, prefix: string): Promise<{ ids: string[]; denied: boolean }> {
  const list = async (path: string) => vaultCall('LIST', `${mount}/metadata/${path}`, { token })
  const top = await list(prefix)
  if (top.status === 403) return { ids: [], denied: true }
  if (top.status !== 200) return { ids: [], denied: false }
  const types = ((top.json as { data?: { keys?: string[] } }).data?.keys ?? []).filter(k => k.endsWith('/'))
  const ids: string[] = []
  for (const t of types.slice(0, 20)) {
    const names = await list(`${prefix}/${t}`)
    if (names.status !== 200) continue
    for (const n of ((names.json as { data?: { keys?: string[] } }).data?.keys ?? []).slice(0, 50)) {
      if (!n.endsWith('/')) ids.push(`${t}${n}`)
    }
  }
  return { ids, denied: false }
}

export default defineEventHandler(async (event): Promise<RotationResponse> => {
  const session = await requireSession(event)
  const checkedAt = new Date().toISOString()
  const feature = await rotationFeature()

  let status: ControllerStatus | null = null
  let compliance: ComplianceReport | null = null
  let controllerReason: string | null = feature.reason ?? null
  if (feature.feature === 'installed') {
    const [s, c] = await Promise.all([controllerGet('/status'), controllerGet('/compliance')])
    status = s.status === 200 ? s.json as ControllerStatus : null
    compliance = c.status === 200 ? c.json as ComplianceReport : null
    if (!status) controllerReason = s.reason ?? `status ${s.status}`
  }

  const mount = status?.config.mount ?? DEFAULT_MOUNT
  const prefix = status?.config.prefix ?? DEFAULT_PREFIX
  let ids = status?.config.secrets.map(s => s.id) ?? []
  let historyDenied = false
  if (!ids.length) {
    const found = await discover(session.vaultToken, mount, prefix)
    ids = found.ids
    historyDenied = found.denied
  }

  const paths = ids.map(id => `${mount}/metadata/${prefix}/${id}`)
  let caps: Record<string, string[]> = {}
  if (paths.length) {
    const reply = await vaultCall('POST', 'sys/capabilities-self', { token: session.vaultToken, body: { paths } })
    // Vault answers per path under `data` (newer) or at the top level (older).
    if (reply.status === 200) {
      const body = reply.json as { data?: Record<string, string[]> } & Record<string, unknown>
      caps = (body.data ?? body) as Record<string, string[]>
    }
  }

  const secrets: RotationSecretView[] = await Promise.all(ids.map(async (id, i) => {
    const path = paths[i]!
    const can = { view: canViewHistory(caps[path]), request: canRequest(caps[path]) }
    const cfg = status?.config.secrets.find(s => s.id === id)
    const live = status?.secrets.find(s => s.secret === id) ?? null
    const comp = compliance?.secrets.find(s => s.secret === id) ?? null
    let history: RotationSecretView['history'] = 'denied'
    let versions: RotationSecretView['versions'] = []
    let currentVersion: number | null = null
    let owner: string | null = cfg?.owner ?? null
    let maxVersions: number | null = null
    if (can.view) {
      const meta = await vaultCall('GET', path, { token: session.vaultToken })
      if (meta.status === 200) {
        const data = (meta.json as { data?: Record<string, unknown> }).data ?? {}
        versions = timeline(data as Parameters<typeof timeline>[0])
        currentVersion = Number(data.current_version ?? 0) || null
        owner = owner ?? ((data.custom_metadata as Record<string, string> | undefined)?.rotation_owner ?? null)
        maxVersions = Number(data.max_versions ?? 0) || null
        history = 'live'
      } else {
        history = meta.status === 403 ? 'denied' : 'unavailable'
      }
    }
    return {
      id,
      path: `${mount}/${prefix}/${id}`,
      type: cfg?.type ?? id.split('/')[0]!,
      owner,
      strategies: cfg?.strategies ?? [],
      intervalSeconds: cfg?.interval_seconds ?? null,
      maxReads: cfg?.max_reads ?? null,
      events: cfg?.events ?? [],
      currentVersion,
      maxVersions,
      history,
      versions,
      controller: live,
      compliance: comp,
      can,
    }
  }))

  const native = await Promise.all(NATIVE_TRANSIT_KEYS.map(async (name) => {
    const reply = await vaultCall('GET', `transit/keys/${name}`, { token: session.vaultToken })
    return nativeKey(name, reply.status, reply.json)
  }))

  return {
    state: feature.feature === 'installed' && status ? 'live' : feature.feature === 'not-installed' ? 'not-installed' : 'unavailable',
    feature: feature.feature,
    reason: controllerReason,
    checkedAt,
    mount,
    prefix,
    historyDenied,
    controller: status?.controller ?? null,
    types: status?.config.types ?? null,
    summary: compliance?.summary ?? null,
    secrets,
    native,
  }
})
