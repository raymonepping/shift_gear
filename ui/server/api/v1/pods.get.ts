// server/api/v1/pods.get.ts — Pod cards from evidence ConfigMap.
// Real pod data is written by sg_ux at Ansible run time; this endpoint reads it.
import { requireSession } from '../../utils/session'
import { readEvidence } from '../../utils/evidence'
import type { PodsResponse } from '../../../shared/types'

export default defineEventHandler(async (event) => {
  await requireSession(event)
  const ev = await readEvidence()

  return {
    observedAt: ev?.observedAt ?? new Date().toISOString(),
    pods: ev?.pods?.cards ?? [],
  } satisfies PodsResponse
})
