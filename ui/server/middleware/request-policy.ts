const requests = new Map<string, { count: number; until: number }>()

export default defineEventHandler((event) => {
  const path = getRequestURL(event).pathname
  const mutation = !['GET', 'HEAD', 'OPTIONS'].includes(event.method)
  if (!mutation && path !== '/auth/login') return
  if (mutation && path !== '/auth/kc-backchannel-logout') {
    const expected = new URL(String(useRuntimeConfig().oidcRedirectUri)).origin
    if (getHeader(event, 'origin') !== expected) throw createError({ statusCode: 403, statusMessage: 'request origin refused' })
  }
  const now = Date.now()
  for (const [key, entry] of requests) if (entry.until < now) requests.delete(key)
  const key = `${getCookie(event, 'sg_session') ?? event.node.req.socket.remoteAddress}:${path}`
  const entry = requests.get(key) ?? { count: 0, until: now + 60000 }
  if (entry.count >= 30 || requests.size >= 2048 && !requests.has(key)) {
    throw createError({ statusCode: 429, statusMessage: 'too many requests; retry later' })
  }
  entry.count++
  requests.set(key, entry)
})
