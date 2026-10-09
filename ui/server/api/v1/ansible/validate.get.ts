// server/api/v1/ansible/validate.get.ts — Ansible validation results.
// Reads from evidence ConfigMap written by sg_validate role.
import { requireSession } from '../../../utils/session'
import { readEvidence } from '../../../utils/evidence'
import type { AnsibleValidateResponse } from '../../../../shared/types'

export default defineEventHandler(async (event) => {
  await requireSession(event)
  const ev = await readEvidence()

  const rows = ev?.ansible?.validate?.rows ?? []
  const passCount = rows.filter((r: Record<string, unknown>) => r.result === 'pass').length
  const failCount = rows.filter((r: Record<string, unknown>) => r.result === 'fail').length
  const warnCount = rows.filter((r: Record<string, unknown>) => r.result === 'warn').length

  return {
    generatedAt: ev?.ansible?.validate?.generatedAt ?? null,
    rows,
    passCount,
    failCount,
    warnCount,
  } satisfies AnsibleValidateResponse
})
