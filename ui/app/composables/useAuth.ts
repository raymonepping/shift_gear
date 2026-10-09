import type { SessionInfo } from '../../shared/types'

/** The signed-in person. Vault token never reaches here. */
export function useAuth() {
  const session = useState<SessionInfo | null>('session', () => null)

  async function load(force = false) {
    if (session.value && !force) return session.value
    try {
      session.value = await $fetch<SessionInfo>('/api/session')
    } catch {
      session.value = null
    }
    return session.value
  }

  const canRotate = computed(() => session.value?.roles.isOperator || session.value?.roles.isAdmin || false)
  const canAudit = computed(() => true) // auditors and above can read audit
  const isAuditorOnly = computed(() => session.value?.roles.isAuditor && !session.value?.roles.isEngineer && !session.value?.roles.isOperator && !session.value?.roles.isAdmin)

  return { session, load, canRotate, canAudit, isAuditorOnly }
}
