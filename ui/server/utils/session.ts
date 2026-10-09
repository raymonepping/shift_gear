// server/utils/session.ts — Shift Gear BFF sessions.
// The person's Vault token and display data live here — never in the browser.
// Cookie: opaque id, httpOnly, SameSite=Lax.
import { randomBytes } from 'node:crypto'
// The event type of Nitro's own h3 (a separately resolved 'h3' would not match).
type H3Event = Parameters<typeof getCookie>[0]

export interface SgSession {
  id: string
  vaultToken: string
  username: string
  displayName: string
  entityId: string | null
  groups: string[]
  policies: string[]
  identityPolicies: string[]
  expiresAt: number
}

const COOKIE = 'sg_session'
const store = () => useStorage<SgSession>('sessions')
const secure = (event: H3Event) =>
  getRequestProtocol(event, { xForwardedProto: true }) === 'https'

export async function createSession(event: H3Event, data: Omit<SgSession, 'id'>) {
  const id = randomBytes(32).toString('base64url')
  const session: SgSession = { ...data, id }
  await store().setItem(id, session)
  setCookie(event, COOKIE, id, {
    httpOnly: true,
    sameSite: 'lax',
    secure: secure(event),
    path: '/',
    maxAge: Math.max(60, Math.floor((data.expiresAt - Date.now()) / 1000)),
  })
  return session
}

export async function getSession(event: H3Event): Promise<SgSession | null> {
  const id = getCookie(event, COOKIE)
  if (!id) return null
  const s = await store().getItem(id)
  if (!s) return null
  if (s.expiresAt < Date.now()) {
    await store().removeItem(id)
    return null
  }
  return s
}

export async function destroySession(event: H3Event) {
  const id = getCookie(event, COOKIE)
  if (id) await store().removeItem(id)
  // Match the original cookie's Secure flag so browsers on HTTPS actually
  // clear it. A Secure cookie is only deleted when the clearing Set-Cookie
  // also carries the Secure attribute.
  deleteCookie(event, COOKIE, { path: '/', secure: secure(event), sameSite: 'lax' })
}

export async function requireSession(event: H3Event): Promise<SgSession> {
  const s = await getSession(event)
  if (!s) throw createError({ statusCode: 401, statusMessage: 'sign in first' })
  return s
}
