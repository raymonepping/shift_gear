import { randomBytes } from 'node:crypto'
import { requireSession } from '../../../../../utils/session'
import { vaultCall } from '../../../../../utils/vault'
import { rotationValue, validOperationId } from '../../../../../../shared/rotation'

const inflight = new Map<string, Promise<unknown>>()
const completed = new Map<string, { until: number; receipt: unknown }>()

export default defineEventHandler(async (event) => {
  const session = await requireSession(event)
  if (![...session.policies, ...session.identityPolicies].some(p => ['sg-operator', 'root'].includes(p))) {
    throw createError({ statusCode: 403, statusMessage: 'operator role required' })
  }
  const name = getRouterParam(event, 'name')
  if (name !== 'app-config') throw createError({ statusCode: 404, statusMessage: 'unsupported target' })
  const { operationId } = await readBody(event) ?? {}
  if (!validOperationId(operationId)) throw createError({ statusCode: 400, statusMessage: 'UUID operationId required' })
  for (const [key, value] of completed) if (value.until <= Date.now()) completed.delete(key)
  const key = `${session.id}:${operationId}`
  if (completed.has(key)) return completed.get(key)!.receipt
  if (inflight.has(key)) return inflight.get(key)
  if (inflight.size + completed.size >= 2048) throw createError({ statusCode: 429 })
  const operation = (async () => {
    const path = 'kv/data/shift-gear/config/app-config'
    const current = await vaultCall('GET', path, { token: session.vaultToken })
    if (current.status !== 200) throw createError({ statusCode: current.status || 503, statusMessage: 'Vault read refused' })
    const record = current.json as { data?: { data?: Record<string, unknown>; metadata?: { version?: number } } }
    const version = record.data?.metadata?.version
    if (!Number.isInteger(version) || !version) throw createError({ statusCode: 503, statusMessage: 'current version unavailable' })
    const data = record.data?.data ?? {}
    const at = new Date().toISOString()
    let nextVersion: number | null = version
    if (data.rotation_id !== operationId) {
      let write
      try {
        write = await vaultCall('POST', path, { token: session.vaultToken, body: {
          options: { cas: version }, data: rotationValue(data, randomBytes(36).toString('base64url'), operationId, session.username, at),
        } })
      } catch {
        const receipt = { operationId, name, state: 'accepted-unverified', writeConfirmed: false, version: null, at }
        completed.set(key, { until: session.expiresAt, receipt })
        return receipt
      }
      if (write.status === 400) throw createError({ statusCode: 409, statusMessage: 'version conflict; reload before a new operation' })
      if (write.status !== 200) throw createError({ statusCode: write.status || 503, statusMessage: 'Vault write refused' })
      nextVersion = (write.json as { data?: { version?: number } }).data?.version ?? null
    }
    const receipt = { operationId, name, state: 'accepted-unverified', writeConfirmed: true, version: nextVersion, at }
    completed.set(key, { until: session.expiresAt, receipt })
    return receipt
  })()
  inflight.set(key, operation)
  try { return await operation } finally { inflight.delete(key) }
})
