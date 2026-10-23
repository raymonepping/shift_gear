<script setup lang="ts">
import type { ObservabilityResponse } from '../../shared/observability'
useHead({ title: 'Metrics and retained audit · Shift Gear' })
definePageMeta({ middleware: ['auth'] })
const { data, status, error, refresh } = await useFetch<ObservabilityResponse>('/api/v1/observability', { server: false, lazy: true })
const now = ref(Date.now())
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => { now.value = Date.now() }, 10000) })
onBeforeUnmount(() => clearInterval(timer))
const fresh = (at: string) => now.value - Date.parse(at) <= 30000 && Date.parse(at) <= now.value + 5000
const filter = ref('')
const entries = computed(() => (data.value?.archive.entries ?? []).filter(row => !filter.value || `${row.namespace}${row.path}`.toLowerCase().includes(filter.value.toLowerCase())))
</script>

<template>
  <div class="observability">
    <section class="vg-hero fleet-hero">
      <div class="hero-head"><div><p class="eyebrow">Private metrics · retained metadata</p><h1>Metrics and retained audit</h1><p>Optional metrics samples and the collector's bounded disk archive have separate source states. The live audit ring still resets when the collector restarts.</p></div><button class="secondary-button" :disabled="status === 'pending'" @click="refresh()">Refresh observations</button></div>
      <NuxtLink to="/audit">Back to the live audit feed</NuxtLink>
    </section>
    <SourceState :status="status" :has-data="!!data" :code="error?.statusCode" label="Observability sources" @retry="refresh()" />
    <section class="panel vg-glass" aria-labelledby="metrics-heading">
      <div class="panel-head"><h2 id="metrics-heading">Metrics destination</h2><span v-if="data">{{ data.metrics.state }}</span></div>
      <p>OpenTelemetry is the preferred optional integration; Prometheus is an alternative. Both can be disabled independently of the core lab. Samples below retain their actual scrape time; a successful query does not make an old sample current.</p>
      <p v-if="data">Backend: {{ data.metrics.backend }}. Checked {{ data.checkedAt }}. Counters describe the current collector process; retained-entry and byte gauges describe its archive.</p>
      <p v-if="data?.metrics.state === 'disabled'" role="status">Metrics integration is disabled. Core lab operations do not require a telemetry backend.</p>
      <p v-else-if="data?.metrics.state !== 'available'" role="status">Metrics cannot currently be verified.</p>
      <div v-else class="vg-table-wrap" tabindex="0" role="region" aria-label="Numeric metric samples"><table class="vg-table"><thead><tr><th scope="col">Metric</th><th scope="col">Value</th><th scope="col">Sample time</th><th scope="col">Freshness</th></tr></thead><tbody>
        <tr v-for="sample in data.metrics.samples" :key="sample.name"><td class="mono">{{ sample.name }}</td><td>{{ sample.value }}</td><td>{{ sample.at }}</td><td>{{ fresh(sample.at) ? 'Recent' : 'Stale or clock uncertain' }}</td></tr>
        <tr v-if="!data.metrics.samples.length"><td colspan="4">No recent samples were returned. Scraping is not established by this response.</td></tr>
      </tbody></table></div>
    </section>
    <section class="panel vg-glass" aria-labelledby="archive-heading">
      <div class="panel-head"><h2 id="archive-heading">Retained audit metadata</h2><span v-if="data">{{ data.archive.state }}</span></div>
      <p>Latest 200 retained records, independently of the live ring. Raw payloads, credentials, actor names, policies and error text are excluded. Paths remain operational metadata and can still be sensitive.</p>
      <p v-if="data?.archive.status && !data.archive.status.available" role="status">Archive storage is unavailable. Displayed committed rows do not establish current writes.</p>
      <p v-if="data?.archive.status">Retention is bounded by {{ data.archive.status.retentionSeconds / 86400 }} days or {{ data.archive.status.maxBytes / 1048576 }} MiB, whichever is reached first. Retained: {{ data.archive.status.retained }} records / {{ data.archive.status.bytes }} bytes. Oldest segment: {{ data.archive.status.oldestAt ?? 'none' }}.</p>
      <p v-if="data?.archive.status && (data.archive.status.failed || data.archive.status.queueDropped || data.archive.status.corrupt)" class="inline-notice inline-notice--warn" role="status">Archive gaps or corruption recorded in this process: failures {{ data.archive.status.failed }}, queue drops {{ data.archive.status.queueDropped }}, corrupt records {{ data.archive.status.corrupt }}. This is not a complete audit trail.</p>
      <p>Committed records survive pod replacement on this PVC. Queued records can be lost on a crash. Host/storage loss, backups, tamper evidence and isolated restoration are not proved here.</p>
      <p v-if="data?.archive.state === 'disabled'" role="status">Audit archive is disabled. The live ring remains available without persistent storage.</p>
      <p v-else-if="data?.archive.state !== 'available'" role="status">Retained metadata cannot currently be read. The live ring and stdout device are separate paths.</p>
      <template v-else>
        <label for="archive-filter">Retained path contains</label><input id="archive-filter" v-model="filter" type="search" maxlength="120" />
        <p role="status">{{ entries.length }} matching retained records in this view</p>
        <p id="archive-scroll-help">Scroll inside the table to review retained records; the path filter narrows this view.</p>
        <div class="vg-table-wrap archive-scroll" tabindex="0" role="region" aria-label="Retained metadata entries" aria-describedby="archive-scroll-help"><table class="vg-table"><thead><tr><th scope="col">Recorded by Vault</th><th scope="col">Recorded by collector</th><th scope="col">Operation / path</th><th scope="col">Error present</th></tr></thead><tbody>
          <tr v-for="entry in entries" :key="entry.id"><td>{{ entry.time ?? 'Not reported' }}</td><td>{{ entry.retainedAt }}</td><td>{{ entry.operation }} {{ entry.namespace }}{{ entry.path }}</td><td>{{ entry.hasError ? 'Yes' : 'No' }}</td></tr>
          <tr v-if="!entries.length"><td colspan="4">No retained records match this view.</td></tr>
        </tbody></table></div>
      </template>
      <NuxtLink to="/help#observability">Metrics and retention runbook</NuxtLink>
    </section>
  </div>
</template>
<style scoped>
.observability { display: grid; grid-template-columns: minmax(0, 1fr); gap: 20px; }
.panel { min-width: 0; }
a { text-decoration: underline; text-underline-offset: 0.15em; }
label { display: block; font-weight: 600; margin: 12px 0 6px; }
input { box-sizing: border-box; max-width: 100%; min-width: 0; padding: 8px; color: var(--vg-text-primary); background: var(--vg-bg-card); border: 1px solid var(--vg-border); }
.vg-table { min-width: 760px; }
td { overflow-wrap: anywhere; }
.archive-scroll { max-height: 32rem; overflow: auto; }
.archive-scroll thead { position: sticky; top: 0; z-index: 1; background: var(--vg-bg-elevated); }
</style>
