// shared/kv-rotation.ts — pure helpers for Engines › Rotation (the KV rotation
// add-on, ADR D17). No I/O; unit-tested in unit/kv-rotation.test.mjs.
//
// History lives in KV v2 custom metadata, one key per retained version:
//   v<N> = "<fp12>|<trigger>|<iso-time>|<actor>"
// The browser only ever sees fingerprints, never a value.

export type RotationFeature = 'installed' | 'degraded' | 'not-installed'
export type RotationTrigger = 'created' | 'time' | 'usage' | 'request' | 'event' | 'recovered'

export interface RotationRecord {
  version: number
  fingerprint: string
  trigger: string
  at: string
  actor: string
}

export interface RotationVersion extends RotationRecord {
  createdTime: string | null
  destroyed: boolean
  recorded: boolean
}

const TRIGGER_LABELS: Record<string, string> = {
  created: 'Created',
  time: 'Schedule',
  usage: 'After use',
  request: 'Requested',
  event: 'Vault event',
  recovered: 'Recovered',
}

export function triggerLabel(trigger: string | null | undefined): string {
  if (!trigger) return 'Not recorded'
  return TRIGGER_LABELS[trigger] ?? trigger
}

/** Decode the v<N> records from custom metadata; malformed keys are ignored. */
export function decodeRecords(custom: Record<string, string> | null | undefined): Map<number, RotationRecord> {
  const out = new Map<number, RotationRecord>()
  for (const [key, raw] of Object.entries(custom ?? {})) {
    const match = /^v(\d+)$/.exec(key)
    if (!match || typeof raw !== 'string') continue
    const parts = raw.split('|')
    if (parts.length !== 4) continue
    const [fingerprint, trigger, at, actor] = parts as [string, string, string, string]
    if (!/^[0-9a-f?]{1,12}$|^unknown$/.test(fingerprint)) continue
    out.set(Number(match[1]), { version: Number(match[1]), fingerprint, trigger, at, actor })
  }
  return out
}

/**
 * Newest-first timeline from KV v2 metadata: every retained version, with its
 * record when one exists. A version without a record was written outside the
 * controller (or is being recorded right now) and says so.
 */
export function timeline(meta: {
  versions?: Record<string, { created_time?: string; destroyed?: boolean }>
  custom_metadata?: Record<string, string> | null
} | null | undefined): RotationVersion[] {
  if (!meta?.versions) return []
  const records = decodeRecords(meta.custom_metadata)
  return Object.entries(meta.versions)
    .map(([key, info]) => {
      const version = Number(key)
      const rec = records.get(version)
      return {
        version,
        fingerprint: rec?.fingerprint ?? 'not recorded',
        trigger: rec?.trigger ?? '',
        at: rec?.at ?? info.created_time ?? '',
        actor: rec?.actor ?? '',
        createdTime: info.created_time ?? null,
        destroyed: Boolean(info.destroyed),
        recorded: Boolean(rec),
      }
    })
    .filter(v => Number.isInteger(v.version) && v.version > 0)
    .sort((a, b) => b.version - a.version)
}

/** "<uuid>|<actor>|<reason>" — the value a person's own token writes to rotation_request. */
export function encodeRequest(requestId: string, actor: string, reason: string): string {
  const clean = (s: string, n: number) => s.replace(/[|\r\n]/g, '').slice(0, n)
  return [clean(requestId, 64), clean(actor, 120), clean(reason, 200)].join('|')
}

export function isManagedSecretId(value: unknown): value is string {
  return typeof value === 'string' && /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\/[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(value)
}

/** Seconds → "45s", "3m 20s", "2h 5m", "3d 4h". */
export function duration(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined || !Number.isFinite(seconds)) return '—'
  const s = Math.max(0, Math.round(seconds))
  if (s < 60) return `${s}s`
  if (s < 3600) return `${Math.floor(s / 60)}m${s % 60 ? ` ${s % 60}s` : ''}`
  if (s < 86400) return `${Math.floor(s / 3600)}h${Math.floor((s % 3600) / 60) ? ` ${Math.floor((s % 3600) / 60)}m` : ''}`
  return `${Math.floor(s / 86400)}d${Math.floor((s % 86400) / 3600) ? ` ${Math.floor((s % 86400) / 3600)}h` : ''}`
}

/** Relative "in 40s" / "40s ago" against now (ms). */
export function relative(epochSeconds: number | null | undefined, nowMs: number): string {
  if (epochSeconds === null || epochSeconds === undefined) return '—'
  const delta = epochSeconds - nowMs / 1000
  if (Math.abs(delta) < 1) return 'now'
  return delta > 0 ? `in ${duration(delta)}` : `${duration(-delta)} ago`
}

export function compliancePill(compliant: boolean | null | undefined): { label: string; tone: 'healthy' | 'rejected' | 'pending' } {
  if (compliant === true) return { label: 'Compliant', tone: 'healthy' }
  if (compliant === false) return { label: 'Non-compliant', tone: 'rejected' }
  return { label: 'Not reported', tone: 'pending' }
}

/** The person may request a rotation when Vault grants `patch` on the managed metadata path. */
export function canRequest(capabilities: string[] | null | undefined): boolean {
  return Boolean(capabilities?.some(c => c === 'patch' || c === 'root'))
}

export function canViewHistory(capabilities: string[] | null | undefined): boolean {
  return Boolean(capabilities?.some(c => c === 'read' || c === 'root'))
}

// ── API shapes (BFF → page) ──────────────────────────────────────────────────

export interface RotationSecretView {
  id: string
  path: string
  type: string
  strategies: string[]
  intervalSeconds: number | null
  maxReads: number | null
  events: Array<{ match: string; path: string }>
  currentVersion: number | null
  maxVersions: number | null
  history: 'live' | 'denied' | 'unavailable'
  versions: RotationVersion[]
  controller: Record<string, unknown> | null
  compliance: Record<string, unknown> | null
  can: { view: boolean; request: boolean }
}

export interface RotationResponse {
  state: 'live' | 'not-installed' | 'unavailable'
  feature: RotationFeature
  reason: string | null
  checkedAt: string
  mount: string
  prefix: string
  historyDenied: boolean
  controller: Record<string, unknown> | null
  types: Record<string, unknown> | null
  summary: Record<string, unknown> | null
  secrets: RotationSecretView[]
}
