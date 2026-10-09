// server/api/v1/cluster.get.ts — the seal chain, Raft health and licence expiry.
// Observe-only: everything comes from the evidence snapshot ansible ux writes
// (scripts/evidence.py reads Vault and OpenShift); nothing is probed or invented here.
import { requireSession } from '../../utils/session'
import { readEvidence } from '../../utils/evidence'
import type { ClusterResponse, ClusterNode } from '../../../shared/types'

export default defineEventHandler(async (event): Promise<ClusterResponse> => {
  await requireSession(event)
  const ev = await readEvidence()
  const nodes: ClusterNode[] = ev?.vault?.nodes ?? []
  const csv = ev?.operator?.csvStatus
  return {
    observedAt: ev?.observedAt ?? new Date().toISOString(),
    sealVault: {
      reachable: ev?.sealVault?.reachable ?? false,
      sealed: ev?.sealVault?.sealed ?? true,
      version: ev?.sealVault?.version ?? null,
    },
    sealAgent: {
      available: ev?.sealAgent?.available ?? false,
      tokenTtl: ev?.sealAgent?.tokenTtl ?? null,
      secretIdAge: ev?.sealAgent?.secretIdAge ?? null,
      lastRotation: ev?.sealAgent?.lastRotation ?? null,
    },
    vaultCluster: {
      nodes,
      unsealed: nodes.filter(n => !n.sealed && n.reachable).length,
      total: nodes.length,
      leader: nodes.find(n => n.role === 'leader')?.name ?? null,
    },
    vsoCsvStatus: csv === 'Succeeded' || csv === 'Installing' || csv === 'Failed' ? csv : 'Unknown',
    licenceExpiry: ev?.vault?.licenceExpiry ?? null,
    auditCollector: {
      connections: ev?.audit?.connections ?? 0,
      received: ev?.audit?.received ?? 0,
    },
  }
})
