// shared/types.ts — Shift Gear UI type contracts.
// These types flow from the server API to the browser. No secret values.

export type EvidenceStatus = 'pass' | 'warn' | 'fail' | 'unknown'
export type LayerTool = 'terraform' | 'ansible'
export type GateName = 'idempotency' | 'drift' | 'secret-scan' | 'validation'
export type UserRole = 'admin' | 'operator' | 'engineer' | 'auditor' | 'viewer'

// ── Session ────────────────────────────────────────────────────────────────
export interface SessionInfo {
  username: string
  displayName: string
  groups: string[]
  policies: string[]
  identityPolicies: string[]
  expiresAt: string
  roles: {
    isAdmin: boolean
    isOperator: boolean
    isEngineer: boolean
    isAuditor: boolean
  }
}

// ── Fleet ──────────────────────────────────────────────────────────────────
export interface FleetTile {
  label: string
  value: string | number
  sub: string
  tone: 'default' | 'good' | 'warn' | 'bad'
  source: string
}

export interface SealNodeStatus {
  name: string
  role: 'seal-vault' | 'seal-agent' | 'vault-cluster'
  status: EvidenceStatus
  detail: string
  sealed?: boolean | null
  ttl?: number | null
}

export interface FleetResponse {
  observedAt: string
  tiles: FleetTile[]
  sealChain: {
    sealVault: SealNodeStatus
    sealAgent: SealNodeStatus
    clusterNodes: SealNodeStatus[]
  }
  podSummary: { total: number; reachable: number }
  operatorSummary: { staticSecrets: number; dynamicSecrets: number }
}

// ── Layers ─────────────────────────────────────────────────────────────────
export interface LayerRow {
  phase: string
  tool: LayerTool
  resources: number | null
  lastApply: { result: string; at: string } | null
  lastPlan: { result: 'clean' | 'drift' | 'error' | 'unknown'; at: string } | null
  lastRun: { at: string; changed: number; failed: number } | null
  lastCheck: { at: string; changed: number } | null
  allowedChanges: string | null
  durationSeconds: number | null
}

export interface LayerGate {
  name: GateName
  result: 'pass' | 'fail' | 'unknown'
  at: string | null
  script: string
  durationSeconds: number | null
}

export interface LayersResponse {
  readable: boolean
  generatedAt: string | null
  phases: LayerRow[]
  gates: LayerGate[]
  digest: { applied: string | null; current: string | null }
}

// ── Engines ────────────────────────────────────────────────────────────────
export type EnginesState = 'live' | 'unreachable' | 'denied' | 'unconfigured'

export interface EngineMount {
  path: string
  type: string
  description: string
  pluginVersion: string | null
  enterprise: boolean
}

export interface EngineSkipped {
  path: string
  reason: string
}

export interface EnginesResponse {
  state: EnginesState
  namespace: string | null
  checkedAt: string
  engines: EngineMount[]
  skipped: EngineSkipped[]
}

// ── Pods ───────────────────────────────────────────────────────────────────
export type PodRole = 'SEAL VAULT' | 'CLUSTER · LEADER' | 'CLUSTER' | 'SEAL AGENT' | 'IDENTITY' | 'OPERATOR' | 'API' | 'UI' | 'WORKLOAD' | 'OTHER'

export interface PodIndicator {
  kind: 'provisioned' | 'openshift' | 'ansible' | 'vault'
  label: string
  status: EvidenceStatus
  detail: string
  evidenceSource: string
}

export interface PodCard {
  name: string
  namespace: string
  podIP: string | null
  role: PodRole
  reachable: boolean
  indicators: [PodIndicator, PodIndicator, PodIndicator, PodIndicator]
  resources: { cpuRequest: string | null; memRequest: string | null; pvcSize: string | null }
}

export interface PodsResponse {
  observedAt: string
  pods: PodCard[]
}

// ── Routes ─────────────────────────────────────────────────────────────────
export type TlsTermination = 'Passthrough' | 'Edge' | 'Re-encrypt'

export interface RouteBackend {
  podName: string
  ready: boolean
  role: 'leader' | 'standby' | 'backend' | 'unknown'
}

export interface RouteEntry {
  name: string
  label: string
  url: string
  namespace: string
  tlsTermination: TlsTermination
  backends: RouteBackend[]
}

export interface RoutesResponse {
  observedAt: string
  routes: RouteEntry[]
}

// ── Operator ───────────────────────────────────────────────────────────────
export interface VsoSecret {
  name: string
  namespace: string
  kind: 'VaultStaticSecret' | 'VaultDynamicSecret'
  vaultPath: string
  destinationSecret: string
  lastSyncTime: string | null
  syncError: string | null
  provenance: 'Vault Operator'
}

export interface WorkloadStatus {
  name: string
  namespace: string
  replicas: number
  readyReplicas: number
  mountedSecretKeys: string[]
  lastSecretUpdate: string | null
}

export interface OperatorResponse {
  observedAt: string
  staticSecrets: VsoSecret[]
  dynamicSecrets: VsoSecret[]
  workloads: WorkloadStatus[]
}

// ── Ansible ────────────────────────────────────────────────────────────────
export interface AnsibleCheck {
  id: string
  label: string
  result: EvidenceStatus
  detail: string
}

export interface AnsibleValidateResponse {
  generatedAt: string | null
  rows: AnsibleCheck[]
  passCount: number
  failCount: number
  warnCount: number
}

export interface AnsibleConvergenceResponse {
  appliedDigest: string | null
  currentDigest: string | null
  converged: boolean
  lastRun: string | null
}

// ── Agent ──────────────────────────────────────────────────────────────────
export interface AgentCard {
  name: string
  kind: 'seal-agent' | 'sidecar'
  status: EvidenceStatus
  detail: string
  tokenTtl: number | null
  secretIdAge: string | null
  lastRotation: string | null
  lastInjection: string | null
  keyNames: string[]
}

export interface AgentResponse {
  observedAt: string
  agents: AgentCard[]
}

// ── Audit ──────────────────────────────────────────────────────────────────
export interface AuditEntry {
  id: string
  time: string
  type: string
  operation: string
  namespace: string
  path: string
  displayName: string | null
  policies: string[]
  error: string | null
  hmacFields: string[]
}

export type AuditState = 'live' | 'unreachable' | 'unconfigured'

export interface AuditResponse {
  /** live: read from the sg-audit collector just now. */
  state: AuditState
  collector: {
    listening: boolean
    connections: number
    received: number
    stored: number
    dropped: number
    malformed?: number
    startedAt?: string
    lastEntryAt?: string | null
  }
  entries: AuditEntry[]
}

// ── Cluster ────────────────────────────────────────────────────────────────
export interface ClusterNode {
  name: string
  role: 'leader' | 'standby'
  sealed: boolean
  reachable: boolean
  version: string | null
  raftAppliedIndex: number | null
}

export interface ClusterResponse {
  observedAt: string
  sealVault: {
    reachable: boolean
    sealed: boolean
    version: string | null
  }
  sealAgent: {
    available: boolean
    tokenTtl: number | null
    secretIdAge: string | null
    lastRotation: string | null
  }
  vaultCluster: {
    nodes: ClusterNode[]
    unsealed: number
    total: number
    leader: string | null
  }
  vsoCsvStatus: 'Succeeded' | 'Installing' | 'Failed' | 'Unknown'
  licenceExpiry: string | null
  auditCollector: {
    connections: number
    received: number
  }
}
