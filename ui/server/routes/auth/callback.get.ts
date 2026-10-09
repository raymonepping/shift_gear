// Keycloak → here: exchange the code for a Vault token, create a session.
export default defineEventHandler(async (event) => {
  const q = getQuery(event) as Record<string, string | undefined>
  const state = q.state ?? ''
  const code = q.code ?? ''
  const error = q.error
  const desc = q.error_description
  if (error) return sendRedirect(event, `/signin?error=${encodeURIComponent(desc || error)}`)

  const nonce = getCookie(event, 'sg_oidc_nonce') ?? ''
  deleteCookie(event, 'sg_oidc_nonce', { path: '/auth' })

  const r = await vaultCall('GET', 'auth/oidc/oidc/callback', {
    query: { state, code, client_nonce: nonce },
  })
  const json = r.json as Record<string, unknown>
  const auth = json?.auth as Record<string, unknown> | undefined
  const errors = json?.errors as string[] | undefined

  if (r.status !== 200 || !auth?.client_token) {
    return sendRedirect(event, `/signin?error=${encodeURIComponent(errors?.[0] ?? 'Vault rejected the sign-in')}`)
  }

  const token = auth.client_token as string
  const metadata = auth.metadata as Record<string, string> | undefined
  const leaseDuration = (auth.lease_duration as number | undefined) ?? 1800

  // Derive role from policies for role-based UI rendering
  const allPolicies = [
    ...((auth.token_policies as string[]) ?? []),
    ...((auth.identity_policies as string[]) ?? []),
  ]

  await createSession(event, {
    vaultToken: token,
    username: metadata?.username ?? 'unknown',
    displayName: metadata?.name ?? metadata?.username ?? 'unknown',
    entityId: (auth.entity_id as string | undefined) ?? null,
    groups: (auth.identity_policies as string[] | undefined) ?? [],
    policies: (auth.token_policies as string[]) ?? [],
    identityPolicies: (auth.identity_policies as string[]) ?? [],
    expiresAt: Date.now() + leaseDuration * 1000,
  })

  // Suppress unused variable lint for allPolicies (it will be used when role logic is added)
  void allPolicies

  return sendRedirect(event, '/')
})
