// POST /api/v1/rotation/:type/:name/request — ask the KV rotation controller to
// rotate one managed secret (an event trigger).
//
// The request is written to Vault with the person's own token as custom
// metadata (rotation_request), so Vault decides who may ask: it needs `patch`
// on the managed metadata path (policy sg-rotation-operator, inherited through
// the internal group sg-rotation-operators). The controller serves it on its
// next loop. The receipt says "accepted"; the page reports "rotated" only when
// Vault shows the new version.
import { requireSession } from '../../../../../utils/session'
import { vaultCall } from '../../../../../utils/vault'
import { validOperationId } from '../../../../../../shared/rotation'
import { canRequest, encodeRequest, isManagedSecretId } from '../../../../../../shared/kv-rotation'

const completed = new Map<string, { until: number; receipt: unknown }>()
const PREFIX = 'shift-gear/rotation'

export default defineEventHandler(async (event) => {
  const session = await requireSession(event)
  const id = `${getRouterParam(event, 'type')}/${getRouterParam(event, 'name')}`
  if (!isManagedSecretId(id)) throw createError({ statusCode: 404, statusMessage: 'unknown managed secret' })
  const body = await readBody(event) ?? {}
  const operationId = body.operationId
  if (!validOperationId(operationId)) throw createError({ statusCode: 400, statusMessage: 'UUID operationId required' })
  const reason = typeof body.reason === 'string' && body.reason.trim() ? body.reason.trim().slice(0, 200) : 'requested in the console'

  for (const [key, value] of completed) if (value.until <= Date.now()) completed.delete(key)
  const key = `${session.id}:${operationId}`
  if (completed.has(key)) return completed.get(key)!.receipt
  if (completed.size >= 2048) throw createError({ statusCode: 429 })

  const path = `kv/metadata/${PREFIX}/${id}`
  // Vault decides — the UI only hides the button.
  const caps = await vaultCall('POST', 'sys/capabilities-self', { token: session.vaultToken, body: { paths: [path] } })
  const capsBody = caps.json as { data?: Record<string, string[]> } & Record<string, string[] | undefined>
  const granted = caps.status === 200 ? (capsBody.data ?? capsBody)[path] : undefined
  if (!canRequest(granted)) throw createError({ statusCode: 403, statusMessage: 'Vault does not allow you to request this rotation' })

  const meta = await vaultCall('GET', path, { token: session.vaultToken })
  if (meta.status === 404) throw createError({ statusCode: 404, statusMessage: 'not a managed secret' })
  if (meta.status !== 200) throw createError({ statusCode: meta.status || 503, statusMessage: 'Vault read refused' })
  const data = (meta.json as { data?: { current_version?: number; custom_metadata?: Record<string, string> } }).data ?? {}
  if ((data.custom_metadata ?? {}).rotation_managed_by !== 'kv-rotation-controller') {
    throw createError({ statusCode: 409, statusMessage: 'this secret is not managed by the rotation controller' })
  }

  const patch = await vaultCall('PATCH', path, {
    token: session.vaultToken,
    contentType: 'application/merge-patch+json',
    body: { custom_metadata: { rotation_request: encodeRequest(operationId, session.username, reason) } },
  })
  if (patch.status === 403) throw createError({ statusCode: 403, statusMessage: 'Vault refused the request' })
  if (patch.status < 200 || patch.status > 299) throw createError({ statusCode: patch.status || 503, statusMessage: 'Vault write refused' })

  const receipt = { operationId, secret: id, state: 'accepted', version: data.current_version ?? null, at: new Date().toISOString() }
  completed.set(key, { until: session.expiresAt, receipt })
  return receipt
})
