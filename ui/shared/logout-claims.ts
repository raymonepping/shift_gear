import type { JWTPayload } from 'jose'

export function logoutSubject(payload: JWTPayload, now = Date.now()) {
  const events = payload.events as Record<string, unknown> | undefined
  const logout = events?.['http://schemas.openid.net/event/backchannel-logout']
  if (typeof payload.sub !== 'string' || !payload.sub || typeof payload.jti !== 'string' || !payload.jti
    || typeof payload.iat !== 'number' || !Number.isFinite(payload.iat) || 'nonce' in payload
    || !logout || typeof logout !== 'object' || Array.isArray(logout)
    || Math.abs(now / 1000 - payload.iat) > 120) throw new Error('invalid logout claims')
  return payload.sub as string
}
