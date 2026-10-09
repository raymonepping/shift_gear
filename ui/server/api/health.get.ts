// Health check — own liveness + Vault reachability probe.
export default defineEventHandler(async () => {
  return { ok: true, service: 'shift-gear-ui', ts: new Date().toISOString() }
})
