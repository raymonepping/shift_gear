import type { RuntimeResponse } from '../../shared/runtime'
import { sealChainStatus } from '../../shared/seal-chain'

/** One foreground polling loop per app shell; every view shares its observations. */
export function useRuntime() {
  const data = useState<RuntimeResponse | null>('runtime', () => null)
  const status = useState<'idle' | 'pending' | 'success' | 'error'>('runtime-status', () => 'idle')
  const now = useState('runtime-clock', () => Date.now())
  const failed = useState('runtime-failed', () => false)
  const chain = computed(() => sealChainStatus(data.value?.sources, now.value, failed.value))

  async function refresh() {
    if (status.value === 'pending') return
    status.value = 'pending'
    try {
      data.value = await $fetch<RuntimeResponse>('/api/v1/runtime', { timeout: 5000, retry: 0 })
      failed.value = false
      status.value = 'success'
    } catch (error) {
      failed.value = true
      status.value = 'error'
      if ((error as { statusCode?: number }).statusCode === 401) await navigateTo('/signin?reason=expired')
    } finally { now.value = Date.now() }
  }

  let timer: ReturnType<typeof setInterval> | undefined
  let next = 0
  function tick() {
    now.value = Date.now()
    if (document.hidden || now.value < next || status.value === 'pending') return
    next = now.value + 15000
    void refresh()
  }
  function startLive() {
    stopLive()
    next = 0
    tick()
    timer = setInterval(tick, 1000)
    document.addEventListener('visibilitychange', onVisibility)
  }
  function onVisibility() {
    if (!document.hidden) { next = 0; tick() }
  }
  function stopLive() {
    clearInterval(timer)
    if (import.meta.client) document.removeEventListener('visibilitychange', onVisibility)
  }

  return { data, status, now, failed, chain, refresh, startLive, stopLive }
}
