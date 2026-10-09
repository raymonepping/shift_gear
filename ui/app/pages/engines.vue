<script setup lang="ts">
import type { EnginesResponse } from '../../shared/types'

useHead({ title: 'Engines · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const { data, status, refresh } = await useFetch<EnginesResponse>('/api/v1/engines', { server: false, lazy: true })
const checking = computed(() => status.value === 'pending')

let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => refresh(), 30_000) })
onBeforeUnmount(() => clearInterval(timer))

const ENGINE_LABELS: Record<string, string> = {
  kv: 'Key/Value', transit: 'Transit', pki: 'PKI', 'pki-int': 'PKI Intermediate',
  database: 'Database', kmip: 'KMIP', keymgmt: 'Key Management', transform: 'Transform',
  identity: 'Identity', sys: 'System', cubbyhole: 'Cubbyhole', totp: 'TOTP', ssh: 'SSH',
}

const ENGINE_DESC: Record<string, string> = {
  kv: 'Application configuration secrets (KV v2)',
  transit: 'Encryption as a service — encrypt/decrypt without exposing keys',
  pki: 'X.509 certificates — root CA',
  'pki-int': 'X.509 certificates — intermediate CA',
  database: 'Dynamic PostgreSQL credentials with configurable TTL',
}

const ENTERPRISE_TYPES = new Set(['kmip', 'keymgmt', 'transform', 'pki_ext'])

function engineLabel(type: string, path: string): string {
  return ENGINE_LABELS[path] ?? ENGINE_LABELS[type] ?? type
}
function engineDesc(path: string, desc: string): string {
  return ENGINE_DESC[path] ?? desc ?? ''
}
function isEnterprise(type: string): boolean {
  return ENTERPRISE_TYPES.has(type)
}
</script>

<template>
  <div>
    <section class="vg-hero fleet-hero" aria-labelledby="engines-title">
      <div class="hero-head">
        <div>
          <p class="eyebrow">Vault Enterprise · namespace engines</p>
          <h1 id="engines-title">Secrets engines</h1>
          <p>Every engine Vault reports as mounted, read live with a token that can list these mounts and nothing else. Terraform mounts them; Vault is the evidence.</p>
        </div>
        <button class="secondary-button" type="button" :disabled="checking" @click="refresh()">
          <svg class="button-icon" :class="{ spinning: checking }" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5" /></svg>
          {{ checking ? 'Checking…' : 'Refresh' }}
        </button>
      </div>
      <p v-if="data" class="hero-status" :class="{ attention: data.state !== 'live' }" role="status">
        {{ data.engines.length }} live · checked {{ data.checkedAt ? new Date(data.checkedAt).toLocaleTimeString() : '—' }} · from Vault
      </p>
    </section>

    <div v-if="checking && !data" class="skeleton" aria-label="Loading"><div v-for="i in 5" :key="i" /></div>

    <template v-if="data">
      <section v-if="data.state !== 'live'" class="panel vg-glass" role="status">
        <p class="state-note">{{ data.state === 'denied'
          ? 'Your token may not list mounts — showing the evidence snapshot from the last make lab.'
          : data.state === 'unreachable' ? 'Vault is unreachable — showing the evidence snapshot from the last make lab.'
            : 'Live read unavailable — showing the evidence snapshot from the last make lab.' }}</p>
      </section>

      <!-- Mounted engines (live, or the evidence snapshot) -->
      <section v-if="data.state === 'live' || data.engines.length" class="panel vg-glass" aria-labelledby="mounted-title">
        <div class="panel-head">
          <div><h2 id="mounted-title">Mounted engines</h2></div>
          <span class="source-tag">sys/mounts · namespace {{ data.namespace ?? 'shift-gear' }}</span>
        </div>
        <div class="engine-grid">
          <article v-for="eng in data.engines" :key="eng.path" class="engine-card vg-card">
            <div class="engine-head">
              <span class="vg-pill vg-pill--healthy engine-live">● Live</span>
              <span v-if="isEnterprise(eng.type) || eng.enterprise" class="vg-pill enterprise-badge">Enterprise</span>
            </div>
            <p class="engine-name">{{ engineLabel(eng.type, eng.path) }}</p>
            <p class="engine-path mono">{{ eng.path }}/</p>
            <p class="engine-desc">{{ engineDesc(eng.path, eng.description) }}</p>
            <dl class="engine-meta">
              <div><dt>Type</dt><dd>{{ eng.type }}</dd></div>
              <div v-if="eng.pluginVersion"><dt>Plugin</dt><dd class="mono">{{ eng.pluginVersion }}</dd></div>
            </dl>
          </article>
        </div>
      </section>

      <!-- Skipped engines -->
      <section v-if="data.skipped?.length" class="panel vg-glass" aria-labelledby="skipped-title">
        <div class="panel-head">
          <div>
            <h2 id="skipped-title">Not mounted, on purpose</h2>
            <p>Engines Terraform deliberately did not mount, with the reason. No mystery omissions.</p>
          </div>
        </div>
        <div class="vg-table-wrap">
          <table class="vg-table">
            <thead><tr><th>Engine</th><th>Reason</th></tr></thead>
            <tbody>
              <tr v-for="s in data.skipped" :key="s.path"><td class="mono">{{ s.path }}</td><td>{{ s.reason }}</td></tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>

<style scoped>
.engine-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 14px; }
.engine-card { padding: 16px 18px; display: flex; flex-direction: column; gap: 8px; }
.engine-head { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.engine-live { font-size: 11px; padding: 2px 8px; }
.enterprise-badge { background: color-mix(in srgb, var(--vg-hue-amber) 10%, transparent); color: var(--vg-governance); border: 1px solid color-mix(in srgb, var(--vg-hue-amber) 28%, transparent); font-size: 10.5px; padding: 2px 8px; }
.engine-name { margin: 0; font-size: 15px; font-weight: 720; color: var(--vg-text-primary); }
.engine-path { margin: 0; font-size: 12px; color: var(--vg-action-bright); }
.engine-desc { margin: 0; font-size: 12.5px; color: var(--vg-text-muted); }
.engine-meta { margin: 0; display: flex; gap: 12px; font-size: 12px; color: var(--vg-text-muted); }
.engine-meta div { display: flex; gap: 4px; }
.engine-meta dt { font-weight: 600; }
</style>
