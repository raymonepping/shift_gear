// server/api/v1/operator/secrets.get.ts — VSO CRDs + workload status.
// Reads from evidence ConfigMap; workload restart is triggered by sg_ux.
import { requireSession } from '../../../utils/session'
import { readEvidence } from '../../../utils/evidence'
import type { OperatorResponse } from '../../../../shared/types'

export default defineEventHandler(async (event) => {
  await requireSession(event)
  const ev = await readEvidence()

  return {
    observedAt: ev?.observedAt ?? new Date().toISOString(),
    staticSecrets: ev?.operator?.static ?? [],
    dynamicSecrets: ev?.operator?.dynamic ?? [],
    workloads: ev?.operator?.workloads ?? [],
  } satisfies OperatorResponse
})
