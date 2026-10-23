// Reject structural corruption before endpoints or pages use nested arrays.
const record = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const count = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 0
const rows = (v: unknown, required: Record<string, string> = {}): v is Record<string, unknown>[] => Array.isArray(v) && v.every(r => record(r)
  && Object.entries(required).every(([key, type]) => typeof r[key] === type))

export function proofShape(value: unknown): boolean {
  return value === undefined || value === null || (record(value)
    && ['pass', 'fail', 'running'].includes(String(value.result))
    && typeof value.at === 'string' && Number.isFinite(Date.parse(value.at)) && Date.parse(value.at) <= Date.now() + 5000
    && typeof value.inputDigest === 'string' && /^[a-f0-9]{64}$/.test(value.inputDigest)
    && count(value.passedChecks) && value.passedChecks <= 64
    && (value.result !== 'pass' || value.passedChecks > 0)
    && value.scope === 'dedicated-fixtures' && value.expiryFixtureSeconds === 5)
}

export function snapshotShape(raw: unknown, name = 'evidence.json'): boolean {
  if (!record(raw)) return false
  if (name === 'layers.json') return rows(raw.phases, { phase: 'string', tool: 'string' }) && record(raw.gates) && record(raw.digest)
  const { vault, sealVault, sealAgent, engines, operator, pods, ansible } = raw
  return proofShape(raw.componentProof) && record(vault) && count(vault.total) && count(vault.unsealed) && vault.unsealed <= vault.total
    && rows(vault.nodes, { name: 'string', role: 'string', reachable: 'boolean', sealed: 'boolean' })
    && vault.nodes.length === vault.total
    && record(sealVault) && typeof sealVault.reachable === 'boolean' && typeof sealVault.sealed === 'boolean'
    && record(sealAgent) && typeof sealAgent.available === 'boolean'
    && record(engines) && count(engines.count) && count(engines.enterprise)
    && record(operator) && count(operator.staticSecrets) && count(operator.dynamicSecrets)
    && rows(operator.static, { name: 'string' }) && rows(operator.dynamic, { name: 'string' }) && rows(operator.workloads, { name: 'string' })
    && record(pods) && count(pods.total) && count(pods.reachable) && pods.reachable <= pods.total
    && rows(pods.cards, { name: 'string' })
    && rows(raw.routes, { name: 'string', url: 'string' }) && raw.routes.every(r => record(r) && rows(r.backends, { podName: 'string', ready: 'boolean' }))
    && rows(raw.agents, { name: 'string', status: 'string' })
    && record(ansible) && record(ansible.convergence) && record(ansible.validate) && rows(ansible.validate.rows, { result: 'string' })
}
