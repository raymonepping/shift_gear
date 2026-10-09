// server/api/v1/fleet.get.ts — Fleet overview from evidence ConfigMap + Vault health.
// Role: any authenticated user.
import { requireSession } from '../../utils/session'
import { readEvidence } from '../../utils/evidence'
import type { FleetResponse, FleetTile } from '../../../shared/types'

export default defineEventHandler(async (event) => {
  await requireSession(event)
  const ev = await readEvidence()

  const tiles: FleetTile[] = [
    {
      label: 'Vault cluster',
      value: `${ev?.vault?.unsealed ?? '?'}/${ev?.vault?.total ?? '?'}`,
      sub: `unsealed · leader ${ev?.vault?.leader ?? 'none'}`,
      tone: ev?.vault?.unsealed === ev?.vault?.total ? 'good' : 'bad',
      source: 'evidence/vault.json',
    },
    {
      label: 'Secret engines',
      value: ev?.engines?.count ?? '—',
      sub: `${ev?.engines?.enterprise ?? 0} enterprise engines`,
      tone: 'default',
      source: 'evidence/engines.json',
    },
    {
      label: 'VSO secrets',
      value: (ev?.operator?.staticSecrets ?? 0) + (ev?.operator?.dynamicSecrets ?? 0),
      sub: `${ev?.operator?.staticSecrets ?? 0} static · ${ev?.operator?.dynamicSecrets ?? 0} dynamic`,
      tone: 'default',
      source: 'evidence/operator.json',
    },
    {
      label: 'Pods',
      value: ev?.pods?.total ?? '—',
      sub: `${ev?.pods?.reachable ?? 0} reachable`,
      tone: (ev?.pods?.reachable ?? 0) === (ev?.pods?.total ?? 0) ? 'good' : 'warn',
      source: 'evidence/pods.json',
    },
    {
      label: 'Seal agent',
      value: ev?.sealAgent?.available ? 'running' : 'down',
      sub: ev?.sealAgent?.tokenTtl ? `token TTL ${ev.sealAgent.tokenTtl}s` : 'no token',
      tone: ev?.sealAgent?.available ? 'good' : 'bad',
      source: 'evidence/agent.json',
    },
  ]

  const body: FleetResponse = {
    observedAt: ev?.observedAt ?? new Date().toISOString(),
    tiles,
    sealChain: {
      sealVault: {
        name: 'sg-vault-seal',
        role: 'seal-vault',
        status: ev?.sealVault?.sealed === false && ev?.sealVault?.reachable ? 'pass' : 'fail',
        detail: ev?.sealVault?.version ?? '—',
        sealed: ev?.sealVault?.sealed ?? null,
        ttl: null,
      },
      sealAgent: {
        name: 'sg-seal-agent',
        role: 'seal-agent',
        status: ev?.sealAgent?.available ? 'pass' : 'fail',
        detail: ev?.sealAgent?.lastRotation ?? '—',
        sealed: null,
        ttl: ev?.sealAgent?.tokenTtl ?? null,
      },
      clusterNodes: (ev?.vault?.nodes ?? []).map((n: Record<string, unknown>) => ({
        name: String(n.name ?? ''),
        role: 'vault-cluster' as const,
        status: n.reachable && !n.sealed ? 'pass' : 'fail',
        detail: String(n.version ?? ''),
        sealed: Boolean(n.sealed),
        ttl: null,
      })),
    },
    podSummary: { total: ev?.pods?.total ?? 0, reachable: ev?.pods?.reachable ?? 0 },
    operatorSummary: {
      staticSecrets: ev?.operator?.staticSecrets ?? 0,
      dynamicSecrets: ev?.operator?.dynamicSecrets ?? 0,
    },
  }

  return body
})
