// server/api/v1/operator/static-secrets/[name]/rotate.post.ts
// Rotate a static secret the honest way: write a new KV version with the
// signed-in operator's own Vault token (sg-operator may update
// kv/data/shift-gear/*). VSO then syncs it (refreshAfter) and rolls the
// workload. Same effect as `make wl-a-rotate`; no Kubernetes credential needed.
import { randomBytes } from 'node:crypto'
import { requireSession } from '../../../../../utils/session'
import { vaultCall } from '../../../../../utils/vault'

// Static secrets the console may rotate, and the KV path each one syncs from.
const ROTATABLE: Record<string, string> = {
  'app-config': 'kv/data/shift-gear/config/app-config',
}

export default defineEventHandler(async (event) => {
  const session = await requireSession(event)
  const policies = [...session.policies, ...session.identityPolicies]
  if (!policies.includes('sg-operator') && !policies.includes('root')) {
    throw createError({ statusCode: 403, statusMessage: 'operator role required' })
  }

  const name = getRouterParam(event, 'name') ?? ''
  const path = ROTATABLE[name]
  if (!path) throw createError({ statusCode: 404, statusMessage: `${name} cannot be rotated from the console` })

  const current = await vaultCall('GET', path, { token: session.vaultToken })
  if (current.status !== 200) {
    throw createError({ statusCode: current.status, statusMessage: 'cannot read the current version' })
  }
  const data = ((current.json as { data?: { data?: Record<string, unknown> } }).data?.data) ?? {}
  const rotatedAt = new Date().toISOString()
  const next = {
    ...data,
    session_secret: randomBytes(36).toString('base64url'),
    rotated_at: rotatedAt,
    rotated_by: session.username,
  }

  const write = await vaultCall('POST', path, { token: session.vaultToken, body: { data: next } })
  if (write.status !== 200) {
    throw createError({ statusCode: write.status, statusMessage: 'Vault refused the new version' })
  }
  const version = (write.json as { data?: { version?: number } }).data?.version ?? null
  return { rotated: true, name, at: rotatedAt, version }
})
