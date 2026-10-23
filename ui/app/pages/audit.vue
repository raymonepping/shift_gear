<script setup lang="ts">
import type { AuditResponse } from '../../shared/types'

useHead({ title: 'Audit · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const currentPage = ref(0)
const pageSize = 25
const typeFilter = ref<string>('')
const pathFilter = ref('')
const restartDetected = ref(false)
const previousInstance = ref<string | null>(null)
const { data, status, refresh, error } = await useFetch<AuditResponse>('/api/v1/audit', { server: false, lazy: true })
const checking = computed(() => status.value === 'pending')
let timer: ReturnType<typeof setInterval> | undefined
let nextPoll = 0
onMounted(() => { timer = setInterval(() => {
  if (document.hidden || checking.value || Date.now() < nextPoll) return
  nextPoll = Date.now() + (status.value === 'error' || data.value?.state !== 'live' ? 30000 : 5000)
  refresh()
}, 1000) })
onBeforeUnmount(() => clearInterval(timer))

const unreachable = computed(() => data.value ? data.value.state !== 'live' : false)
const noConnection = computed(() =>
  data.value?.state === 'live' && (!data.value.collector.listening || data.value.collector.connections === 0),
)
const since = computed(() => {
  const t = data.value?.collector.startedAt
  return t ? new Date(t).toLocaleString() : null
})

const filtered = computed(() => {
  const all = data.value?.entries ?? []
  return all.filter(e => (!typeFilter.value || e.type === typeFilter.value)
    && (!pathFilter.value || `${e.namespace}${e.path}`.toLowerCase().includes(pathFilter.value.toLowerCase())))
})

const entries = computed(() => filtered.value.slice(currentPage.value * pageSize, (currentPage.value + 1) * pageSize))
watch([typeFilter, pathFilter], () => { currentPage.value = 0 })
watch(() => data.value?.collector.instanceId, (id) => {
  if (id && previousInstance.value && id !== previousInstance.value) restartDetected.value = true
  if (id) previousInstance.value = id
})
watch(filtered, rows => { currentPage.value = Math.min(currentPage.value, Math.max(0, Math.ceil(rows.length / pageSize) - 1)) })
watch(() => data.value?.collector.startedAt, () => { currentPage.value = 0 })
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

    <NuxtLink to="/observability" class="retention-link">Metrics and retained audit metadata</NuxtLink>
    <SourceState :status="status" :has-data="!!data" :code="error?.statusCode" label="Audit observations" @retry="refresh()" />

    <p v-if="restartDetected" class="inline-notice inline-notice--warn" role="status">Collector restarted during this visit. Earlier buffered entries and counters were lost. <NuxtLink to="/help#audit">Audit runbook</NuxtLink></p>
    <p v-if="unreachable" class="inline-notice inline-notice--warn" role="status">
      The audit collector cannot be reached right now, so this page shows no entries. The last verified configuration includes a separate stdout audit device; its current health is not checked here.
    </p>
    <p v-else-if="noConnection" class="inline-notice inline-notice--warn" role="status">
      The audit collector has no active connection from Vault right now. This live feed has a gap until Vault reconnects. The configured stdout device is independent.
    </p>
    <p v-else-if="since" class="sg-since">Counting since the collector started, {{ since }}.</p>

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
        <label for="sg-path-filter" class="sg-filter-label">Path contains</label>
        <input id="sg-path-filter" v-model="pathFilter" class="sg-select" type="search" maxlength="120" placeholder="Filter the recent buffer" />
        <button class="sg-btn-ghost" :disabled="checking" @click="refresh()">
          <span :class="checking ? 'sg-spin' : ''" aria-hidden="true">↻</span> Refresh
        </button>
      </div>
      <nav aria-label="Audit pages" class="sg-filter-bar">
        <button :disabled="currentPage === 0" @click="currentPage--">Previous</button>
        <span role="status">Page {{ currentPage + 1 }} · {{ filtered.length }} recent entries available</span>
        <button :disabled="(currentPage + 1) * pageSize >= filtered.length" @click="currentPage++">Next</button>
      </nav>
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
              <td colspan="7" class="sg-empty">{{ unreachable ? 'No entries: the collector is unreachable' : filtered.length === 0 && (typeFilter || pathFilter) ? 'No recent entries match these filters' : 'No entries yet: waiting for Vault traffic' }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>

<style scoped>
.retention-link { text-decoration: underline; }
.sg-audit { display: grid; grid-template-columns: minmax(0, 1fr); gap: 18px; max-width: 1400px; margin: 0 auto; }
.sg-h { margin: 0 0 6px; font-size: 24px; font-weight: 800; letter-spacing: -0.025em; }
.sg-sub { margin: 0; color: var(--vg-text-secondary); max-width: 72ch; }
.sg-panel { min-width: 0; padding: 16px 20px; display: grid; grid-template-columns: minmax(0, 1fr); gap: 12px; }
.sg-filter-bar { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.sg-filter-label { font-size: 12.5px; font-weight: 600; color: var(--vg-text-secondary); }
.sg-select { max-width: 100%; min-width: 0; box-sizing: border-box; font-size: 13px; padding: 4px 8px; border-radius: 6px; border: 1px solid var(--vg-border); background: var(--vg-well); color: var(--vg-text); }
.sg-btn-ghost { font-size: 13px; padding: 4px 10px; border-radius: 6px; border: 1px solid var(--vg-border); background: transparent; color: var(--vg-text-secondary); cursor: pointer; }
.sg-btn-ghost:hover { background: var(--vg-well); }
.sg-btn-ghost:disabled { opacity: .5; cursor: default; }
.sg-path { max-width: 38ch; overflow-wrap: anywhere; }
.sg-policies { max-width: 24ch; overflow-wrap: anywhere; font-size: 11.5px; }
.sg-hmac { max-width: 20ch; overflow-wrap: anywhere; font-size: 11.5px; color: var(--vg-text-muted); }
.sg-err { color: var(--vg-critical); font-size: 12px; max-width: 28ch; }
.sg-since { margin: 0; font-size: 12.5px; color: var(--vg-text-secondary); }
.sg-empty { text-align: center; padding: 24px; color: var(--vg-text-muted); font-size: 13px; }
.sg-spin { display: inline-block; animation: spin 1s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
</style>
