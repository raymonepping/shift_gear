// server/utils/evidence.ts — Read non-secret evidence from the ConfigMap mount.
// The ConfigMap sg-evidence is mounted at NUXT_EVIDENCE_DIR (default: /evidence).
// sg_ux writes a single evidence.json containing all cluster state.
import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { observation } from '../../shared/observation'
import { snapshotShape } from '../../shared/snapshot'

let _dir: string | undefined

function evidenceDir(): string {
  if (!_dir) {
    const cfg = useRuntimeConfig()
    _dir = (cfg.evidenceDir as string | undefined) || '/evidence'
  }
  return _dir
}

// Returns the parsed evidence object, or null when the file is absent/unreadable.
// The caller names the shape it expects; missing fields stay undefined and the
// pages render them as "not reported" (never invented).
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function readEvidence<T = any>(name = 'evidence.json'): Promise<T | null> {
  let raw: Record<string, unknown> | null = null
  try {
    raw = JSON.parse(await readFile(resolve(evidenceDir(), name), 'utf8'))
    if (!snapshotShape(raw, name)) raw = {}
    if (name === 'evidence.json' && raw?.clusterId) {
      try {
        const run = JSON.parse(await readFile(resolve(evidenceDir(), 'run.json'), 'utf8'))
        const embeddedAt = (raw.automationRun as { startedAt?: string } | null)?.startedAt
        if (run.clusterId === raw.clusterId && typeof run.runId === 'string'
          && typeof run.startedAt === 'string' && typeof run.provisioning === 'string'
          && typeof run.publication === 'string' && (!embeddedAt || run.startedAt >= embeddedAt)) raw.automationRun = run
      } catch { /* initial deployment can lack the separate attempt record */ }
    }
    if (name !== 'evidence.json') {
      const main = JSON.parse(await readFile(resolve(evidenceDir(), 'evidence.json'), 'utf8'))
      if (!raw?.observationId || raw.observationId !== main.observationId) raw = {}
    }
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') raw = {}
    // Missing and invalid observations have no made-up observation timestamp.
  }
  const meta = observation(raw)
  return { ...(meta.availability === 'available' ? raw : {}), evidence: meta } as T
}
