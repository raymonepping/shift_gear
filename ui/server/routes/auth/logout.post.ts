// Sign out: revoke the Vault token server-side, destroy the session.
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
  return sendRedirect(event, '/signin')
})
