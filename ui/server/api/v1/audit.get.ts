// server/api/v1/audit.get.ts — Vault's audit stream, as the sg-audit collector
// received it from Vault's socket audit device. Entries arrive HMAC'd by Vault.
// Live only: when the collector is unreachable the page says so, rather than
// showing a snapshot as if it were live.
import { requireSession } from '../../utils/session'
import type { AuditResponse } from '../../../shared/types'

const EMPTY = { listening: false, connections: 0, received: 0, stored: 0, dropped: 0 }

export default defineEventHandler(async (event) => {
  // Every signed-in person may read it, as designed (useAuth canAudit): values
  // arrive HMAC'd by Vault, so the page shows who did what, never a secret.
  await requireSession(event)
  const base = useRuntimeConfig().auditApiBase as string // NUXT_AUDIT_API_BASE, e.g. http://sg-audit.sg-app.svc:8080
  if (!base) {
    return { state: 'unconfigured', collector: EMPTY, entries: [] } satisfies AuditResponse
  }
  try {
    const res = await $fetch<Omit<AuditResponse, 'state'>>(`${base}/audit`, {
      query: { limit: 200 },
      timeout: 3000,
    })
    return { state: 'live', collector: res.collector, entries: res.entries } satisfies AuditResponse
  } catch {
    return { state: 'unreachable', collector: EMPTY, entries: [] } satisfies AuditResponse
  }
})
