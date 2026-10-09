// server/api/v1/ansible/convergence.get.ts — Ansible convergence digest.
// Reads applied vs. current digest from evidence ConfigMap.
import { requireSession } from '../../../utils/session'
import { readEvidence } from '../../../utils/evidence'
import type { AnsibleConvergenceResponse } from '../../../../shared/types'

export default defineEventHandler(async (event) => {
  await requireSession(event)
  const ev = await readEvidence()

  const applied = ev?.ansible?.convergence?.appliedDigest ?? null
  const current = ev?.ansible?.convergence?.currentDigest ?? null

  return {
    appliedDigest: applied,
    currentDigest: current,
    converged: applied !== null && applied === current,
    lastRun: ev?.ansible?.convergence?.lastRun ?? null,
  } satisfies AnsibleConvergenceResponse
})
