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

  // display_name is mapped from the given_name JWT claim via the OIDC role's
  // claim_mappings (vault_auth.yml). username is the preferred_username claim.
  // Neither metadata?.name nor metadata?.full_name is emitted by this Keycloak config.
  // Vault JWT/OIDC plugin stores the user_claim value in auth.metadata under
  // the claim's own name (preferred_username), not a hardcoded "username" key.
  const username = metadata?.preferred_username ?? metadata?.username ?? 'unknown'
  const displayName = metadata?.display_name ?? username

  await createSession(event, {
    vaultToken: token,
    username,
    displayName,
    entityId: (auth.entity_id as string | undefined) ?? null,
    groups: (auth.identity_policies as string[] | undefined) ?? [],
    policies: (auth.token_policies as string[]) ?? [],
    identityPolicies: (auth.identity_policies as string[]) ?? [],
    expiresAt: Date.now() + leaseDuration * 1000,
  })

  void allPolicies

  return sendRedirect(event, '/')
})
