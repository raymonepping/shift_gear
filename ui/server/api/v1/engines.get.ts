// server/api/v1/engines.get.ts — Secret engine mounts from Vault sys/mounts.
// Uses the sg-api-vault token from session. Falls back to evidence on error.
import { requireSession } from '../../utils/session'
import { vaultCall } from '../../utils/vault'
import { readEvidence } from '../../utils/evidence'
import type { EnginesResponse, EngineMount, EngineSkipped } from '../../../shared/types'

const INTERNAL_TYPES = new Set(['system', 'identity', 'cubbyhole', 'ns_system', 'ns_identity', 'ns_cubbyhole', 'agent_registry', 'ns_agent_registry'])

export default defineEventHandler(async (event) => {
  const session = await requireSession(event)

  let mounts: Record<string, Record<string, unknown>>
  let state: 'live' | 'unreachable' | 'denied' | 'unconfigured' = 'live'
  const namespace: string | null = 'shift-gear'

  try {
    // Live with the signed-in user's own token; most people may not list
    // mounts, so a 403 falls back to the evidence snapshot (marked 'denied').
    const res = await vaultCall('GET', 'sys/mounts', { token: session.vaultToken })
    if (res.status !== 200) throw Object.assign(new Error('vault'), { statusCode: res.status })
    const body = res.json as { data?: Record<string, Record<string, unknown>> }
    mounts = body.data ?? {}
  } catch (err: unknown) {
    const e = err as { statusCode?: number }
    if (e?.statusCode === 403) state = 'denied'
    else if (e?.statusCode === 404) state = 'unconfigured'
    else state = 'unreachable'

    // Fall back to evidence ConfigMap
    const ev = await readEvidence()
    return {
      state,
      namespace,
      checkedAt: new Date().toISOString(),
      engines: ev?.engines?.mounts ?? [],
      skipped: ev?.engines?.skipped ?? [],
    } satisfies EnginesResponse
  }

  const engines: EngineMount[] = []
  // What Terraform chose not to mount, and why: the terraform/platform
  // skipped_engines output, carried by the evidence snapshot.
  const skipped: EngineSkipped[] = (await readEvidence())?.engines?.skipped ?? []

  for (const [rawPath, info] of Object.entries(mounts)) {
    if (typeof info !== 'object' || info === null) continue
    // sys / identity / cubbyhole and friends are always present, not user-facing
    if (INTERNAL_TYPES.has(String(info.type ?? ''))) continue
    engines.push({
      path: rawPath,
      type: String(info.type ?? ''),
      description: String(info.description ?? ''),
      pluginVersion: info.plugin_version ? String(info.plugin_version) : null,
      enterprise: ['transform', 'kmip', 'pki_ext'].includes(String(info.type ?? '')),
    })
  }

  return {
    state,
    namespace,
    checkedAt: new Date().toISOString(),
    engines,
    skipped,
  } satisfies EnginesResponse
})
