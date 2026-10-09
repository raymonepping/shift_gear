// Sign out: revoke the Vault token server-side, destroy the session, then
// terminate the Keycloak SSO session so the next Sign-in prompts for
// credentials and a different persona can sign in.
//
// If NUXT_KEYCLOAK_LOGOUT_URL is set (it is, in every deployed pod), the
// browser is sent to Keycloak's end-session endpoint with a
// post_logout_redirect_uri back to /signin. Keycloak clears its SSO cookie
// and immediately redirects back to /signin.
//
// Without the Keycloak redirect, Shift Gear's session is gone but Keycloak's
// SSO cookie survives: clicking Sign in again silently re-authenticates the
// previous user without prompting for credentials.
export default defineEventHandler(async (event) => {
  const s = await getSession(event)
  if (s) {
    // Best-effort token revocation; never fail the logout on Vault errors.
    try {
      await vaultCall('POST', 'auth/token/revoke-self', { token: s.vaultToken })
    } catch {
      // ignored — token may already be expired
    }
  }
  await destroySession(event)

  const cfg = useRuntimeConfig()
  const keycloakLogoutUrl = (cfg.keycloakLogoutUrl as string | undefined) ?? ''
  if (keycloakLogoutUrl) {
    const redirectBack = (cfg.oidcRedirectUri as string)
      ? new URL('/signin', new URL(cfg.oidcRedirectUri as string).origin).href
      : `${getRequestProtocol(event, { xForwardedProto: true })}://${getRequestHost(event)}/signin`
    const dest = `${keycloakLogoutUrl}?post_logout_redirect_uri=${encodeURIComponent(redirectBack)}`
    return sendRedirect(event, dest)
  }
  return sendRedirect(event, '/signin')
})
