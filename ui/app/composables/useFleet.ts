import type { FleetResponse } from '../../shared/types'

/** Shared fleet state — topbar seal chain pill + Fleet page read the same data. */
export function useFleet() {
  const { chain: sealChainLabel } = useRuntime()
  const fleet = useState<FleetResponse | null>('fleet', () => null)
  const checking = useState<boolean>('fleet-checking', () => false)
  const failed = useState<boolean>('fleet-failed', () => false)

  const refreshSeconds = useRuntimeConfig().public.refreshSeconds as number

  async function refresh() {
    if (checking.value) return
    checking.value = true
    try {
      fleet.value = await $fetch<FleetResponse>('/api/v1/fleet')
      failed.value = false
    } catch (e) {
      if ((e as { statusCode?: number }).statusCode === 401) {
        await navigateTo('/signin?reason=expired')
        return
      }
      failed.value = true
    } finally {
      checking.value = false
    }
  }

  let timer: ReturnType<typeof setInterval> | undefined

  function startLive() {
    refresh()
    timer = setInterval(refresh, refreshSeconds * 1000)
  }

  function stopLive() {
    clearInterval(timer)
  }

  return { fleet, checking, failed, refresh, sealChainLabel, startLive, stopLive }
}
