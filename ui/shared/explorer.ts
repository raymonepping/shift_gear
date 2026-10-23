// Published declarations only. Never turn these rows into a capability grant.
export const OWNERS = ['Terraform', 'Ansible', 'VSO', 'Operator', 'Terraform + Ansible'] as const
export const IDENTITIES = ['tf-seal', 'ansible-seal', 'tf-platform', 'ansible-platform'] as const
const RUNBOOKS = ['evidence', 'vault', 'identity', 'delivery', 'components', 'audit', 'observability', 'consumer'] as const
export interface OwnershipRow {
  id: string; area: string; owner: typeof OWNERS[number]; scope: string
  runtimeWriter: string; exception: string; check: string; runbook: typeof RUNBOOKS[number]
}
export interface BoundaryRow { token: typeof IDENTITIES[number]; vault: 'vault' | 'vault-seal'; path: string; expect: string }
export interface ExplorerDeclaration {
  schemaVersion: '1'; inputDigest: string
  sources: { ownership: { path: 'policies/ownership-map.json'; sha256: string }; boundary: { path: 'policies/boundary-matrix.json'; sha256: string } }
  ownership: OwnershipRow[]; boundary: BoundaryRow[]
}
const record = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const digest = (v: unknown): v is string => typeof v === 'string' && /^[a-f0-9]{64}$/.test(v)
const text = (v: unknown): v is string => typeof v === 'string' && v.length > 0 && v.length <= 600 && [...v].every(char => char.charCodeAt(0) >= 32)
const oneOf = <T extends string>(v: unknown, values: readonly T[]): v is T => typeof v === 'string' && values.includes(v as T)

export function explorerDeclaration(raw: unknown): ExplorerDeclaration | null {
  if (!record(raw) || raw.schemaVersion !== '1' || !digest(raw.inputDigest) || !record(raw.sources)) return null
  const { ownership: source, boundary: matrix } = raw.sources
  if (!record(source) || source.path !== 'policies/ownership-map.json' || !digest(source.sha256)
    || !record(matrix) || matrix.path !== 'policies/boundary-matrix.json' || !digest(matrix.sha256)) return null
  if (!Array.isArray(raw.ownership) || raw.ownership.length < 1 || raw.ownership.length > 32
    || !Array.isArray(raw.boundary) || raw.boundary.length < 1 || raw.boundary.length > 64) return null
  const ownership: OwnershipRow[] = []
  for (const r of raw.ownership) {
    if (!record(r) || !text(r.id) || !/^[a-z][a-z0-9-]{0,47}$/.test(r.id)
      || !oneOf(r.owner, OWNERS) || !oneOf(r.runbook, RUNBOOKS)
      || !text(r.area) || !text(r.scope) || !text(r.runtimeWriter) || !text(r.exception) || !text(r.check)) return null
    ownership.push({ id: r.id, area: r.area, owner: r.owner, scope: r.scope, runtimeWriter: r.runtimeWriter, exception: r.exception, check: r.check, runbook: r.runbook })
  }
  const boundary: BoundaryRow[] = []
  for (const r of raw.boundary) {
    if (!record(r) || !oneOf(r.token, IDENTITIES) || !oneOf(r.vault, ['vault', 'vault-seal'])
      || !text(r.path) || !/^[a-zA-Z0-9_/-]+$/.test(r.path) || r.path.includes('..')
      || !text(r.expect) || !/^(allow|deny):(create|read|update|delete|list|sudo|patch)$/.test(r.expect)) return null
    boundary.push({ token: r.token, vault: r.vault, path: r.path, expect: r.expect })
  }
  if (new Set(ownership.map(r => r.id)).size !== ownership.length
    || new Set(boundary.map(r => `${r.token}:${r.vault}:${r.path}`)).size !== boundary.length) return null
  return { schemaVersion: '1', inputDigest: raw.inputDigest,
    sources: { ownership: { path: source.path, sha256: source.sha256 }, boundary: { path: matrix.path, sha256: matrix.sha256 } }, ownership, boundary }
}
