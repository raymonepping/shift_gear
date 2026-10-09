// server/api/v1/agent/status.get.ts — Seal agent and sidecar status.
// Reads from evidence ConfigMap written by sg_seal_agent + sg_ux roles.
import { requireSession } from '../../../utils/session'
import { readEvidence } from '../../../utils/evidence'
import type { AgentResponse } from '../../../../shared/types'

export default defineEventHandler(async (event) => {
  await requireSession(event)
  const ev = await readEvidence()

  return {
    observedAt: ev?.observedAt ?? new Date().toISOString(),
    agents: ev?.agents ?? [],
  } satisfies AgentResponse
})
