// server/utils/evidence.ts — Read non-secret evidence from the ConfigMap mount.
// The ConfigMap sg-evidence is mounted at NUXT_EVIDENCE_DIR (default: /evidence).
// sg_ux writes a single evidence.json containing all cluster state.
import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'

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
  try {
    const raw = await readFile(resolve(evidenceDir(), name), 'utf8')
    return JSON.parse(raw) as T
  } catch {
    return null
  }
}
