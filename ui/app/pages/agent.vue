<script setup lang="ts">
import type { AgentResponse } from '../../shared/types'

useHead({ title: 'Agent · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const { data, status, refresh } = await useFetch<AgentResponse>('/api/v1/agent/status', { server: false, lazy: true })
const checking = computed(() => status.value === 'pending')
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => refresh(), 10_000) })
onBeforeUnmount(() => clearInterval(timer))

const { session } = useAuth()
const canReinject = computed(() => session.value?.roles.isOperator || session.value?.roles.isAdmin || false)

const reinjectLoading = ref(false)

async function reinject(agentName: string) {
  reinjectLoading.value = true
  try {
    await $fetch(`/api/v1/agent/${encodeURIComponent(agentName)}/reinject`, { method: 'POST' })
    await new Promise(r => setTimeout(r, 2_000))
    await refresh()
  } catch (e) {
    console.error('reinject failed', e)
  } finally {
    reinjectLoading.value = false
  }
}

function ttlLabel(ttl: number | null): string {
  if (ttl === null) return 'not reported'
  if (ttl <= 0) return 'expired'
  if (ttl < 60) return `${ttl}s`
  if (ttl < 3600) return `${Math.floor(ttl / 60)}m ${ttl % 60}s`
  return `${Math.floor(ttl / 3600)}h ${Math.floor((ttl % 3600) / 60)}m`
}

function agentTone(status: string): string {
  if (status === 'pass') return 'state-pass'
  if (status === 'fail') return 'state-fail'
  return 'state-unknown'
}
</script>

<template>
  <div>
    <section class="vg-hero fleet-hero" aria-labelledby="agent-title">
      <div class="hero-head">
        <div>
          <p class="eyebrow">Vault Agent · sidecar injection</p>
          <h1 id="agent-title">Agent</h1>
          <p>The seal agent holds an AppRole credential to authenticate to the seal Vault. The agent-demo sidecar injects a secret into the application pod — no Vault token in the container.</p>
        </div>
        <button class="secondary-button" type="button" :disabled="checking" @click="refresh()">
          <svg class="button-icon" :class="{ spinning: checking }" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5" /></svg>
          {{ checking ? 'Checking…' : 'Refresh' }}
        </button>
      </div>
    </section>

    <div v-if="checking && !data" class="skeleton" aria-label="Loading"><div /><div /></div>

    <div v-if="data?.agents.length" class="agent-grid">
      <article
        v-for="agent in data.agents"
        :key="agent.name"
        class="sg-layer-panel sg-layer-panel--agent vg-card"
      >
        <div class="agent-head">
          <span class="sg-provenance-badge">{{ agent.kind === 'seal-agent' ? 'Vault Agent (Seal)' : 'Vault Agent (Sidecar)' }}</span>
          <span class="door-chip" :class="agentTone(agent.status)"><i aria-hidden="true" />{{ agent.detail }}</span>
        </div>
        <h2 class="agent-name">{{ agent.name }}</h2>
        <dl class="agent-meta">
          <div v-if="agent.tokenTtl !== null">
            <dt>Token TTL</dt>
            <dd :class="{ 'ttl-expired': agent.tokenTtl <= 0 }">{{ ttlLabel(agent.tokenTtl) }}</dd>
          </div>
          <div v-if="agent.secretIdAge">
            <dt>Secret-id age</dt>
            <dd>{{ agent.secretIdAge }}</dd>
          </div>
          <div v-if="agent.lastRotation">
            <dt>Last rotation</dt>
            <dd>{{ new Date(agent.lastRotation).toLocaleString() }}</dd>
          </div>
          <div v-if="agent.lastInjection">
            <dt>Last injection</dt>
            <dd>{{ new Date(agent.lastInjection).toLocaleString() }}</dd>
          </div>
        </dl>
        <!-- Key names (never values) -->
        <div v-if="agent.keyNames.length">
          <p class="keys-label">Injected keys</p>
          <div class="keys-list">
            <span v-for="k in agent.keyNames" :key="k" class="key-chip mono">{{ k }}</span>
          </div>
        </div>
        <div v-if="canReinject && agent.kind === 'sidecar'" class="agent-actions">
          <button type="button" class="secondary-button" :disabled="reinjectLoading" @click="reinject(agent.name)">
            <svg v-if="reinjectLoading" class="button-icon spinning" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5" /></svg>
            {{ reinjectLoading ? 'Triggering…' : 'Trigger re-injection' }}
          </button>
        </div>
      </article>
    </div>

    <p v-else-if="data && !data.agents.length" class="state-empty">No agent data — not reported.</p>
  </div>
</template>

<style scoped>
.agent-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 16px; }
.agent-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; flex-wrap: wrap; margin-bottom: 6px; }
.agent-name { margin: 0 0 10px; font-size: 18px; font-weight: 720; font-family: var(--font-mono); color: var(--vg-text-primary); }
.agent-meta { margin: 0 0 12px; display: grid; gap: 4px; font-size: 13px; }
.agent-meta div { display: flex; gap: 8px; align-items: baseline; }
.agent-meta dt { color: var(--vg-text-muted); flex-shrink: 0; min-width: 110px; }
.agent-meta dd { margin: 0; color: var(--vg-text-primary); font-variant-numeric: tabular-nums; }
.ttl-expired { color: var(--vg-critical); }
.keys-label { margin: 0 0 6px; font-size: 11px; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; color: var(--vg-text-muted); }
.keys-list { display: flex; flex-wrap: wrap; gap: 6px; }
.key-chip { padding: 2px 8px; border-radius: 5px; background: var(--vg-well); border: 1px solid var(--vg-border-subtle); font-size: 12px; color: var(--vg-text-secondary); }
.agent-actions { display: flex; justify-content: flex-end; margin-top: auto; }
</style>
