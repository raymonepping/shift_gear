import type { RuntimeSource } from './runtime'

export const sealMembers = ['vault-0', 'vault-1', 'vault-2'] as const
export const sealSourceNames = ['Seal Vault', 'Seal Agent', ...sealMembers.map(name => `Vault member ${name}`)]

/** Health is public metadata. Reject partial responses instead of assuming unsealed. */
export function projectVaultHealth(raw: Record<string, unknown>): RuntimeSource['data'] {
  if (typeof raw.sealed !== 'boolean' || typeof raw.initialized !== 'boolean'
    || typeof raw.standby !== 'boolean' || typeof raw.performance_standby !== 'boolean') throw new Error('shape')
  return { sealed: raw.sealed, initialized: raw.initialized, standby: raw.standby,
    performanceStandby: raw.performance_standby }
}

export function projectSealAgent(raw: Record<string, unknown>): RuntimeSource['data'] {
  const metadata = raw.metadata as { name?: string; generation?: number } | undefined
  const spec = raw.spec as { replicas?: number } | undefined
  const status = raw.status as { observedGeneration?: number; availableReplicas?: number; updatedReplicas?: number } | undefined
  if (metadata?.name !== 'seal-agent' || !Number.isInteger(metadata.generation) || !spec || !status
    || !Number.isInteger(spec.replicas) || (spec.replicas ?? 0) < 1
    || !Number.isInteger(status.observedGeneration)) throw new Error('shape')
  for (const value of [status.availableReplicas, status.updatedReplicas]) {
    if (value !== undefined && (!Number.isInteger(value) || value < 0)) throw new Error('shape')
  }
  return { available: status.observedGeneration === metadata.generation
    && (status.availableReplicas ?? 0) >= spec.replicas!
    && (status.updatedReplicas ?? 0) >= spec.replicas! }
}

// Vault uses non-2xx codes for valid sealed/uninitialized/standby health responses.
// Only its documented health codes may carry a health observation.
export function vaultHealthStatus(status: number): number {
  return [200, 429, 472, 473, 501, 503].includes(status) ? 200 : status
}

export function sourceFresh(source: RuntimeSource | undefined, now: number): boolean {
  if (source?.state !== 'available' || !source.observedAt) return false
  const age = now - Date.parse(source.observedAt)
  return Number.isFinite(age) && age >= -5000 && age <= 30000
}

export function sealChainStatus(sources: RuntimeSource[] = [], now = Date.now(), failed = false): {
  tone: 'unknown' | 'healthy' | 'critical' | 'degraded'; label: string
} {
  const unknown = { tone: 'unknown' as const, label: 'Seal chain: not currently verified' }
  if (failed) return unknown
  const chain = sealSourceNames.map(name => sources.find(source => source.name === name))
  // A fresh positive fault remains meaningful even when another member cannot be read.
  if (chain.some(source => sourceFresh(source, now) && source!.data.sealed === true)) {
    return { tone: 'critical', label: sourceFresh(chain[0], now) && chain[0]?.data.sealed === true ? 'Seal Vault sealed' : 'Vault member sealed' }
  }
  if (chain.some(source => !sourceFresh(source, now))) return unknown
  if (chain[0]!.data.initialized !== true) return { tone: 'critical', label: 'Seal Vault uninitialized' }
  if (chain[1]!.data.available !== true) return { tone: 'degraded', label: 'Seal Agent unavailable' }
  const members = chain.slice(2) as RuntimeSource[]
  const ok = members.filter(source => source.data.initialized === true && source.data.sealed === false).length
  const leaders = members.filter(source => source.data.standby === false && source.data.performanceStandby === false).length
  if (ok !== sealMembers.length || leaders !== 1) return { tone: 'degraded', label: `Seal chain ${ok}/${sealMembers.length} · check cluster` }
  return { tone: 'healthy', label: `Seal chain ${ok}/${sealMembers.length}` }
}
