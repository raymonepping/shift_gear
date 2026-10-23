// Session info — what the browser may know about the signed-in person.
// Never the Vault token; never the identity policies in full.
import { capabilities } from '../../shared/capabilities'

export default defineEventHandler(async (event) => {
  const s = await requireSession(event)
  const allPolicies = [...s.policies, ...s.identityPolicies]
  return {
    username: s.username,
    displayName: s.displayName,
    groups: s.groups,
    policies: s.policies,
    identityPolicies: s.identityPolicies,
    expiresAt: new Date(s.expiresAt).toISOString(),
    roles: capabilities(allPolicies),
  }
})
