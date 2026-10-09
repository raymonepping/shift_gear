// Session info — what the browser may know about the signed-in person.
// Never the Vault token; never the identity policies in full.
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
    roles: {
      isAdmin: allPolicies.includes('sg-operator') || allPolicies.includes('sg-approver'),
      isOperator: allPolicies.includes('sg-operator'),
      isEngineer: allPolicies.includes('sg-engineer'),
      isAuditor: allPolicies.includes('sg-auditor'),
    },
  }
})
