// Layers — phases from .build/layers.json (ConfigMap evidence mount).
import type { LayersResponse, LayerTool } from '../../shared/types'

const GATES = ['idempotency', 'drift', 'secret-scan', 'validation'] as const
type GateResult = 'pass' | 'fail' | 'unknown'

const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/
const iso = (v: unknown): string | null => typeof v === 'string' && ISO.test(v) ? v : null
const num = (v: unknown): number | null => typeof v === 'number' && Number.isInteger(v) && v >= 0 ? v : null
const rec = (v: unknown): Record<string, unknown> =>
  v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {}

const GATE_SCRIPTS: Record<string, string> = {
  'idempotency': 'scripts/idempotency.sh',
  'drift': 'scripts/drift.sh',
  'secret-scan': 'scripts/secret-scan.sh',
  'validation': 'ansible/validate.yml',
}

function parseLayers(raw: unknown): LayersResponse {
  const root = rec(raw)
  if (!Array.isArray(root.phases)) {
    return {
      readable: false,
      generatedAt: null,
      phases: [],
      gates: GATES.map(name => ({ name, result: 'unknown', at: null, script: GATE_SCRIPTS[name]! })),
      digest: { applied: null, current: null },
    }
  }
  const phases = root.phases.map(rec).flatMap((row) => {
    const phase = typeof row.phase === 'string' && /^[a-z][a-z0-9-]{0,31}$/.test(row.phase) ? row.phase : null
    const tool: LayerTool | null = row.tool === 'terraform' || row.tool === 'ansible' ? row.tool : null
    if (!phase || !tool) return []
    const run = rec(row.last_run)
    const chk = rec(row.last_check)
    return [{
      phase,
      tool,
      resources: tool === 'terraform' ? num(row.resources) : null,
      lastApply: tool === 'terraform' && iso(rec(row.last_apply).at)
        ? { result: String(rec(row.last_apply).result || 'success'), at: iso(rec(row.last_apply).at)! }
        : null,
      lastPlan: tool === 'terraform' && iso(rec(row.last_plan).at)
        ? { result: (['clean','drift','error','unknown'].includes(String(rec(row.last_plan).result)) ? String(rec(row.last_plan).result) : 'unknown') as 'clean' | 'drift' | 'error' | 'unknown', at: iso(rec(row.last_plan).at)! }
        : null,
      lastRun: tool === 'ansible' && iso(run.at) && num(run.changed) !== null
        ? { at: iso(run.at)!, changed: num(run.changed)!, failed: num(run.failed) ?? 0 }
        : null,
      lastCheck: tool === 'ansible' && iso(chk.at) && num(chk.changed) !== null
        ? { at: iso(chk.at)!, changed: num(chk.changed)! }
        : null,
      allowedChanges: tool === 'ansible' && typeof row.allowed_changes === 'string' ? row.allowed_changes.slice(0, 200) : null,
    }]
  })
  const gatesRaw = rec(root.gates)
  const gates = GATES.map((name) => {
    const g = rec(gatesRaw[name])
    const result: GateResult = g.result === 'pass' ? 'pass' : g.result === 'fail' ? 'fail' : 'unknown'
    return { name, result, at: iso(g.at), script: GATE_SCRIPTS[name]! }
  })
  const digest = rec(root.digest ?? root.automation_digest)
  return {
    readable: true,
    generatedAt: iso(root.generated_at),
    phases,
    gates,
    digest: {
      applied: typeof digest.applied === 'string' ? digest.applied : null,
      current: typeof digest.current === 'string' ? digest.current : null,
    },
  }
}

export default defineEventHandler(async (event) => {
  await requireSession(event)
  const raw = await readEvidence('layers.json')
  return parseLayers(raw) satisfies LayersResponse
})
