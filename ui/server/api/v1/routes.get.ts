// server/api/v1/routes.get.ts — OpenShift Routes from evidence ConfigMap.
// Route data is written by sg_ux; the UI reads it without direct cluster access.
import { requireSession } from '../../utils/session'
import { readEvidence } from '../../utils/evidence'
import type { RoutesResponse } from '../../../shared/types'

export default defineEventHandler(async (event) => {
  await requireSession(event)
  const ev = await readEvidence()

  return {
    observedAt: ev?.observedAt ?? new Date().toISOString(),
    routes: ev?.routes ?? [],
  } satisfies RoutesResponse
})
