// Sign-in: Vault OIDC → Keycloak → back here.
// The BFF calls Vault's auth_url endpoint to get the Keycloak redirect.
import { randomBytes } from 'node:crypto'

export default defineEventHandler(async (event) => {
  const cfg = useRuntimeConfig()
  const nonce = randomBytes(16).toString('hex')
  const r = await vaultCall('POST', 'auth/oidc/oidc/auth_url', {
    body: {
      role: 'visitor',
      redirect_uri: cfg.oidcRedirectUri,
      client_nonce: nonce,
    },
  })
  const json = r.json as Record<string, unknown>
  const data = json?.data as Record<string, unknown> | undefined
  const url = data?.auth_url as string | undefined
  const errors = json?.errors as string[] | undefined
  if (r.status !== 200 || !url) {
    return sendRedirect(event, `/signin?error=${encodeURIComponent(errors?.[0] ?? 'Vault did not return a sign-in URL')}`)
  }
  setCookie(event, 'sg_oidc_nonce', nonce, {
    httpOnly: true,
    sameSite: 'lax',
    secure: getRequestProtocol(event, { xForwardedProto: true }) === 'https',
    path: '/auth',
    maxAge: 600,
  })
  return sendRedirect(event, url)
})
