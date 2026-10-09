<script setup lang="ts">
import type { AuditResponse } from '../../shared/types'

useHead({ title: 'Audit · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const typeFilter = ref<string>('')
const { data, status, refresh } = await useFetch<AuditResponse>('/api/v1/audit', { server: false, lazy: true })
const checking = computed(() => status.value === 'pending')
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => refresh(), 5_000) })
onBeforeUnmount(() => clearInterval(timer))

const offline = computed(() =>
  data.value ? (!data.value.collector.listening || data.value.collector.connections === 0) : false,
)

const entries = computed(() => {
  const all = data.value?.entries ?? []
  if (!typeFilter.value) return all
  return all.filter(e => e.type === typeFilter.value)
})

const types = computed(() => {
  const s = new Set((data.value?.entries ?? []).map(e => e.type))
  return [...s].sort()
})
</script>

<template>
  <div class="sg-audit">
    <section class="vg-hero">
      <h2 class="sg-h">Vault's own record</h2>
      <p class="sg-sub">
        Every request Vault processed, as its socket audit device sent it.
        Token values and secret data are HMAC'd by Vault — they never appear in the clear.
      </p>
    </section>

    <p v-if="offline" class="inline-notice inline-notice--warn" role="status">
      The audit collector has no active connection from Vault right now. The stdout audit device
      still records everything — but this live feed has a gap until the collector reconnects.
    </p>

    <div v-if="data" class="sg-audit-tiles vg-grid-4">
      <div class="vg-tile"><span class="vg-tile__label">Received</span><span class="vg-tile__value">{{ data.collector.received }}</span></div>
      <div class="vg-tile"><span class="vg-tile__label">Stored</span><span class="vg-tile__value">{{ data.collector.stored }}</span></div>
      <div class="vg-tile" :class="data.collector.dropped > 0 ? 'vg-tile--warn' : ''">
        <span class="vg-tile__label">Dropped</span><span class="vg-tile__value">{{ data.collector.dropped }}</span>
      </div>
      <div class="vg-tile" :class="data.collector.connections > 0 ? 'vg-tile--good' : 'vg-tile--bad'">
        <span class="vg-tile__label">Connections</span><span class="vg-tile__value">{{ data.collector.connections }}</span>
      </div>
    </div>

    <section class="vg-glass sg-panel" aria-label="Audit log">
      <div class="sg-filter-bar">
        <label for="sg-type-filter" class="sg-filter-label">Type</label>
        <select id="sg-type-filter" v-model="typeFilter" class="sg-select">
          <option value="">All types</option>
          <option v-for="t in types" :key="t" :value="t">{{ t }}</option>
        </select>
        <button class="sg-btn-ghost" :disabled="checking" @click="refresh()">
          <span :class="checking ? 'sg-spin' : ''">↻</span> Refresh
        </button>
      </div>
      <div class="vg-table-wrap" tabindex="0" role="region" aria-label="Audit entries">
        <table class="vg-table">
          <thead>
            <tr>
              <th>Time</th>
              <th>Type</th>
              <th>Operation · path</th>
              <th>Who (display name)</th>
              <th>Policies</th>
              <th>HMAC'd fields</th>
              <th>Error</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="e in entries" :key="e.id">
              <td class="vg-table__mono">{{ new Date(e.time).toLocaleTimeString() }}</td>
              <td>{{ e.type }}</td>
              <td class="vg-table__mono sg-path">{{ e.operation }} {{ e.namespace }}{{ e.path }}</td>
              <td class="vg-table__mono">{{ e.displayName ?? 'unauthenticated' }}</td>
              <td class="vg-table__mono sg-policies">{{ (e.policies ?? []).join(', ') || '—' }}</td>
              <td class="vg-table__mono sg-hmac">{{ (e.hmacFields ?? []).join(', ') || '—' }}</td>
              <td class="sg-err">{{ e.error ? e.error.replace(/\s+/g, ' ').slice(0, 80) : '' }}</td>
            </tr>
            <tr v-if="!checking && entries.length === 0">
              <td colspan="7" class="sg-empty">No entries yet — waiting for Vault traffic</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>

<style scoped>
.sg-audit { display: grid; gap: 18px; max-width: 1400px; margin: 0 auto; }
.sg-h { margin: 0 0 6px; font-size: 24px; font-weight: 800; letter-spacing: -0.025em; }
.sg-sub { margin: 0; color: var(--vg-text-secondary); max-width: 72ch; }
.sg-panel { padding: 16px 20px; display: grid; gap: 12px; }
.sg-filter-bar { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.sg-filter-label { font-size: 12.5px; font-weight: 600; color: var(--vg-text-secondary); }
.sg-select { font-size: 13px; padding: 4px 8px; border-radius: 6px; border: 1px solid var(--vg-border); background: var(--vg-well); color: var(--vg-text); }
.sg-btn-ghost { font-size: 13px; padding: 4px 10px; border-radius: 6px; border: 1px solid var(--vg-border); background: transparent; color: var(--vg-text-secondary); cursor: pointer; }
.sg-btn-ghost:hover { background: var(--vg-well); }
.sg-btn-ghost:disabled { opacity: .5; cursor: default; }
.sg-path { max-width: 38ch; overflow-wrap: anywhere; }
.sg-policies { max-width: 24ch; overflow-wrap: anywhere; font-size: 11.5px; }
.sg-hmac { max-width: 20ch; overflow-wrap: anywhere; font-size: 11.5px; color: var(--vg-text-muted); }
.sg-err { color: var(--vg-critical); font-size: 12px; max-width: 28ch; }
.sg-empty { text-align: center; padding: 24px; color: var(--vg-text-muted); font-size: 13px; }
.sg-spin { display: inline-block; animation: spin 1s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
</style>
