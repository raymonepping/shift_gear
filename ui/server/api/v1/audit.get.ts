// server/api/v1/audit.get.ts — Audit log from the socket collector.
// The sg_ux role enables the socket audit device and the API server collects entries.
// This endpoint proxies through the BFF to the API server's in-memory log.
import { requireSession } from '../../utils/session'
import { readEvidence } from '../../utils/evidence'
import type { AuditResponse } from '../../../shared/types'

export default defineEventHandler(async (event) => {
  await requireSession(event)
  const config = useRuntimeConfig()
  const auditApiBase = config.auditApiBase as string // internal: http://sg-api.shift-gear.svc:3001

  // Try live collector endpoint first
  if (auditApiBase) {
    try {
      const res = await $fetch<AuditResponse>(`${auditApiBase}/audit`, { timeout: 3000 })
      return res
    } catch { /* fall through to evidence */ }
  }

  // Fallback: evidence snapshot (possibly stale but shows that the mechanism exists)
  const ev = await readEvidence()
  return {
    collector: {
      listening: ev?.audit?.listening ?? false,
      connections: ev?.audit?.connections ?? 0,
      received: ev?.audit?.received ?? 0,
      stored: ev?.audit?.stored ?? 0,
      dropped: ev?.audit?.dropped ?? 0,
    },
    entries: ev?.audit?.entries ?? [],
  } satisfies AuditResponse
})
