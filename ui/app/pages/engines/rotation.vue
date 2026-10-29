<script setup lang="ts">
import type { RotationResponse, RotationSecretView } from '../../../shared/kv-rotation'
import { compliancePill, duration, relative, triggerLabel } from '../../../shared/kv-rotation'

useHead({ title: 'Rotation · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const { data, status, refresh, error } = await useFetch<RotationResponse>('/api/v1/rotation', { server: false, lazy: true })
const checking = computed(() => status.value === 'pending')
const now = ref(Date.now())

// Normal cadence 10 s; after a request, 2 s for 30 s until Vault shows the new version.
let timer: ReturnType<typeof setInterval> | undefined
let fastUntil = 0
let ticks = 0
onMounted(() => {
  timer = setInterval(() => {
    now.value = Date.now()
    ticks++
    if (Date.now() < fastUntil ? ticks % 2 === 0 : ticks % 10 === 0) refresh()
  }, 1000)
})
onBeforeUnmount(() => clearInterval(timer))

const expanded = ref<string | null>(null)
const reasons = reactive<Record<string, string>>({})
const notices = reactive<Record<string, { tone: 'ok' | 'error' | 'pending'; text: string }>>({})
const busy = reactive<Record<string, boolean>>({})
const pendingFrom = reactive(new Map<string, number>())

const installed = computed(() => data.value?.feature === 'installed' || data.value?.feature === 'degraded')
const managed = computed(() => data.value?.secrets ?? [])
const summary = computed(() => data.value?.summary as null | { total: number; compliant: number; non_compliant: number; compliance_percent: number; oldest_overdue: string | null; by_type: Record<string, { total: number; compliant: number }> })
const controller = computed(() => data.value?.controller as null | { events?: string; usage?: { available: boolean; undercount: boolean }; last_loop?: string; loop_seconds?: number; identity?: string })
const types = computed(() => (data.value?.types ?? {}) as Record<string, { generator: Record<string, unknown>; interval_seconds: number; max_age_seconds: number; min_length: number; max_reads: number | null }>)

const nextRotation = computed(() => {
  const due = managed.value
    .map(s => (s.controller?.next_due as Record<string, unknown> | undefined)?.time as number | undefined)
    .filter((t): t is number => typeof t === 'number')
  return due.length ? Math.min(...due) : null
})

const nonCompliant = computed(() => managed.value.filter(s => s.compliance && (s.compliance as { compliant: boolean }).compliant === false))

function comp(s: RotationSecretView) {
  return s.compliance as null | { compliant: boolean; reasons: string[]; warnings?: string[]; age_seconds: number | null; max_age_seconds: number }
}
function live(s: RotationSecretView) {
  return s.controller as null | { reads_since: number | null; max_reads: number | null; next_due: Record<string, unknown> }
}
function latest(s: RotationSecretView) {
  return s.versions[0] ?? null
}
function strategyLabel(st: string) {
  return st === 'time' ? 'Time' : st === 'usage' ? 'Usage' : st === 'event' ? 'Event' : st
}
function readsText(s: RotationSecretView) {
  if (!s.strategies.includes('usage')) return '—'
  const reads = live(s)?.reads_since
  return reads === null || reads === undefined ? 'not reported' : `${reads} / ${s.maxReads ?? '—'}`
}
function eventText(rec: { trigger: string; actor: string }) {
  if (rec.trigger === 'request') return `Requested by ${rec.actor || 'unknown'}`
  if (rec.trigger === 'event') return 'Vault event: watched path written'
  return triggerLabel(rec.trigger)
}
function nextDue(s: RotationSecretView) {
  const due = live(s)?.next_due?.time
  if (typeof due !== 'number') return '—'
  return due * 1000 <= now.value ? 'due now' : relative(due, now.value)
}
function toggle(id: string) {
  expanded.value = expanded.value === id ? null : id
}

async function requestRotation(s: RotationSecretView) {
  busy[s.id] = true
  notices[s.id] = { tone: 'pending', text: 'Sending the request to Vault…' }
  try {
    const receipt = await $fetch<{ version: number | null }>(`/api/v1/rotation/${s.id}/request`, {
      method: 'POST',
      body: { operationId: crypto.randomUUID(), reason: reasons[s.id] || undefined },
    })
    const from = receipt.version ?? s.currentVersion ?? 0
    pendingFrom.set(s.id, from)
    notices[s.id] = { tone: 'pending', text: `Vault accepted the request at v${from}. Waiting for the controller to write the next version…` }
    fastUntil = Date.now() + 30_000
    refresh()
  } catch (e: unknown) {
    const err = e as { statusCode?: number; statusMessage?: string }
    notices[s.id] = { tone: 'error', text: err.statusCode === 403 ? 'Vault does not allow you to request this rotation.' : `Request failed (${err.statusCode ?? 'network'}): ${err.statusMessage ?? 'try again'}` }
  } finally {
    busy[s.id] = false
  }
}

// Report "rotated" only when Vault itself shows the new version.
watch(managed, (list) => {
  for (const s of list) {
    const from = pendingFrom.get(s.id)
    if (from !== undefined && (s.currentVersion ?? 0) > from && latest(s)?.recorded) {
      notices[s.id] = { tone: 'ok', text: `Rotated: v${from} → v${s.currentVersion} (fingerprint ${latest(s)!.fingerprint}).` }
      pendingFrom.delete(s.id)
    }
  }
})

function downloadReport() {
  const blob = new Blob([JSON.stringify({ summary: data.value?.summary, secrets: managed.value.map(s => s.compliance) }, null, 2)], { type: 'application/json' })
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = `kv-rotation-compliance-${new Date().toISOString().slice(0, 19)}.json`
  a.click()
  URL.revokeObjectURL(a.href)
}
</script>

<template>
  <div>
    <section class="vg-hero" aria-labelledby="rotation-title">
      <div class="hero-head">
        <div>
          <p class="eyebrow">Engines · KV v2</p>
          <h1 id="rotation-title">Rotation</h1>
          <p>Values rotate inside Vault on a schedule, after use, or on request. Each rotation is a new KV v2 version; this page shows fingerprints, never values.</p>
        </div>
        <button class="secondary-button" type="button" :disabled="checking" @click="refresh()">
          <svg class="button-icon" :class="{ spinning: checking }" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5" /></svg>
          {{ checking ? 'Checking…' : 'Refresh' }}
        </button>
      </div>
      <p v-if="data" class="hero-status" :class="{ attention: data.state !== 'live' || (summary && summary.non_compliant > 0) }" role="status">
        <template v-if="data.state === 'live' && summary">
          {{ summary.total }} managed · {{ summary.compliance_percent }}% compliant
          <template v-if="nextRotation"> · next rotation {{ relative(nextRotation, now) }}</template>
          · events {{ controller?.events ?? 'not reported' }}
        </template>
        <template v-else-if="data.state === 'not-installed'">Rotation add-on not installed · history stays in Vault</template>
        <template v-else>Rotation controller {{ data.feature }} · {{ data.reason ?? 'not answering' }}</template>
      </p>
    </section>

    <SourceState :status="status" :has-data="!!data" :code="error?.statusCode" label="Rotation observations" @retry="refresh()" />
    <div v-if="checking && !data" class="skeleton" aria-label="Loading"><div v-for="i in 4" :key="i" /></div>

    <template v-if="data">
      <!-- Not installed / degraded -->
      <section v-if="data.state === 'not-installed'" class="panel vg-glass" role="status" aria-labelledby="not-installed-title">
        <h2 id="not-installed-title">The KV rotation add-on is not installed</h2>
        <p>It rotates KV v2 values inside Vault: on a schedule per secret type, after a number of reads, or when someone with the right Vault policy asks. Install it with <code>make rotation-up</code>; remove it with <code>make rotation-down</code>.</p>
        <p v-if="managed.length">Managed secrets and their history stay in Vault after removal. Below is that history as Vault reports it to you; schedule and compliance need the controller.</p>
        <p v-else-if="data.historyDenied">Your Vault policies do not allow you to list the rotation history.</p>
      </section>
      <p v-else-if="data.state !== 'live'" class="inline-notice inline-notice--warn" role="status">
        The rotation controller is {{ data.feature }} ({{ data.reason ?? 'no answer' }}). History below comes from Vault; schedule and compliance are not reported.
      </p>

      <!-- Compliance -->
      <section v-if="summary" class="panel vg-glass" aria-labelledby="compliance-title">
        <div class="panel-head">
          <div>
            <h2 id="compliance-title">Compliance</h2>
            <p>Each secret against its type's policy: maximum age, maximum reads, retained history, settings and records.</p>
          </div>
          <span class="source-tag">Rotation controller · /compliance</span>
        </div>
        <div class="vg-kpi-strip">
          <div class="vg-kpi-card vg-kpi-card--healthy"><p class="vg-kpi-label">Compliant</p><p class="vg-kpi-value">{{ summary.compliant }} / {{ summary.total }}</p></div>
          <div v-for="(t, name) in summary.by_type" :key="name" class="vg-kpi-card"><p class="vg-kpi-label mono">{{ name }}</p><p class="vg-kpi-value">{{ t.compliant }} / {{ t.total }}</p></div>
        </div>
        <ul v-if="nonCompliant.length" class="reasons" aria-label="Non-compliant secrets">
          <li v-for="s in nonCompliant" :key="s.id"><span class="mono">{{ s.id }}</span>: {{ comp(s)!.reasons.join('; ') }}</li>
        </ul>
        <p v-else class="ok-line">Every managed secret is within its policy.</p>
        <button class="secondary-button" type="button" @click="downloadReport">Download report (JSON)</button>
      </section>

      <!-- Inventory -->
      <section v-if="managed.length" class="panel vg-glass" aria-labelledby="inventory-title">
        <div class="panel-head">
          <div>
            <h2 id="inventory-title">Managed secrets</h2>
            <p>Select a secret to see its version history. Rotate now is offered when Vault grants you <code>patch</code> on its metadata.</p>
          </div>
          <span class="source-tag">Vault KV v2 · {{ data.mount }}/{{ data.prefix }}</span>
        </div>
        <div class="vg-table-wrap" tabindex="0" role="region" aria-label="Managed secrets table">
          <table class="vg-table">
            <thead>
              <tr><th>Secret</th><th>Strategies</th><th>Version</th><th>Fingerprint</th><th>Last change</th><th>Reads</th><th>Next (time)</th><th>Status</th></tr>
            </thead>
            <tbody>
              <template v-for="s in managed" :key="s.id">
                <tr class="row" :class="{ open: expanded === s.id }">
                  <td>
                    <button class="row-toggle" type="button" :aria-expanded="expanded === s.id" :aria-controls="`timeline-${s.type}-${s.id.split('/')[1]}`" @click="toggle(s.id)">
                      <span class="mono">{{ s.id }}</span>
                    </button>
                  </td>
                  <td><span v-for="st in s.strategies" :key="st" class="vg-pill strategy">{{ strategyLabel(st) }}</span><span v-if="!s.strategies.length" class="dim">not reported</span></td>
                  <td class="num">{{ s.currentVersion ? `v${s.currentVersion}` : '—' }}</td>
                  <td class="mono">{{ latest(s)?.fingerprint ?? '—' }}</td>
                  <td>{{ latest(s) ? `${eventText(latest(s)!)} · ${relative(Date.parse(latest(s)!.createdTime ?? latest(s)!.at) / 1000, now)}` : (s.history === 'denied' ? 'history denied by Vault' : '—') }}</td>
                  <td class="num">{{ readsText(s) }}</td>
                  <td class="num">{{ nextDue(s) }}</td>
                  <td><span class="vg-pill" :class="`vg-pill--${compliancePill(comp(s)?.compliant).tone}`">{{ compliancePill(comp(s)?.compliant).label }}</span></td>
                </tr>
                <tr v-if="expanded === s.id" class="detail">
                  <td colspan="8">
                    <div :id="`timeline-${s.type}-${s.id.split('/')[1]}`" class="detail-body">
                      <div class="detail-head">
                        <p class="path mono">{{ s.path }}</p>
                        <div v-if="s.can.request && installed" class="request">
                          <label class="form-field">
                            <span>Reason (optional)</span>
                            <input v-model="reasons[s.id]" type="text" maxlength="200" :name="`reason-${s.id}`" placeholder="e.g. suspected exposure" />
                          </label>
                          <button class="primary-button" type="button" :disabled="busy[s.id] || pendingFrom.has(s.id) || !s.strategies.includes('event')" @click="requestRotation(s)">
                            Rotate now
                          </button>
                        </div>
                      </div>
                      <p v-if="notices[s.id]" class="inline-notice" :class="{ 'inline-notice--warn': notices[s.id]!.tone === 'pending', error: notices[s.id]!.tone === 'error' }" role="status">{{ notices[s.id]!.text }}</p>
                      <p v-if="s.can.request && !s.strategies.includes('event')" class="dim">This secret does not accept requests (no event strategy).</p>
                      <p v-if="comp(s)?.warnings?.length" class="dim">{{ comp(s)!.warnings!.join('; ') }}</p>
                      <ol v-if="s.versions.length" class="timeline" :aria-label="`Version history of ${s.id}`">
                        <li v-for="v in s.versions" :key="v.version" :class="{ unrecorded: !v.recorded }">
                          <span class="ver num">v{{ v.version }}</span>
                          <span class="fp mono">{{ v.fingerprint }}</span>
                          <span class="what">{{ v.recorded ? eventText(v) : 'Not recorded (written outside the controller, or being recorded)' }}</span>
                          <span class="when">{{ v.createdTime ? new Date(v.createdTime).toLocaleString() : '—' }}</span>
                        </li>
                      </ol>
                      <p v-if="s.maxVersions && s.currentVersion && s.currentVersion > s.maxVersions" class="dim">v1–v{{ s.currentVersion - s.maxVersions }} pruned (KV v2 keeps {{ s.maxVersions }} versions).</p>
                      <p v-if="s.history === 'denied'" class="dim">Vault does not allow you to read this secret's history.</p>
                    </div>
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Policies -->
      <section v-if="Object.keys(types).length" class="panel vg-glass" aria-labelledby="policies-title">
        <div class="panel-head">
          <div>
            <h2 id="policies-title">Rotation policies per type</h2>
            <p>Declared in <code>addons/rotation/rotation.yaml</code>. Enforcement: the controller reconciles drift; Vault ACL lets only the controller write values; people may only request.</p>
          </div>
          <span class="source-tag">rotation.yaml · Terraform ConfigMap</span>
        </div>
        <div class="vg-table-wrap" tabindex="0" role="region" aria-label="Rotation policies table">
          <table class="vg-table">
            <thead><tr><th>Type</th><th>Generator</th><th>Schedule</th><th>Max age</th><th>Min length</th><th>Max reads</th></tr></thead>
            <tbody>
              <tr v-for="(t, name) in types" :key="name">
                <td class="mono">{{ name }}</td>
                <td>{{ Object.entries(t.generator).map(([k, v]) => `${k} ${Array.isArray(v) ? v.join('+') : v}`).join(', ') }}</td>
                <td class="num">every {{ duration(t.interval_seconds) }}</td>
                <td class="num">{{ duration(t.max_age_seconds) }}</td>
                <td class="num">{{ t.min_length }}</td>
                <td class="num">{{ t.max_reads ?? '—' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="dim">Boundary: this is KV v2 <strong>value</strong> rotation. Database credentials, PKI certificates and Transit keys are rotated by Vault's own engines; this add-on covers static values those engines cannot.</p>
      </section>
    </template>
  </div>
</template>

<style scoped>
.reasons { margin: 12px 0; padding-left: 18px; color: var(--vg-critical); font-size: 13px; }
.ok-line { color: var(--vg-healthy); font-size: 13px; margin: 12px 0; }
.dim { color: var(--vg-text-dim); font-size: 12.5px; }
.num { font-variant-numeric: tabular-nums; white-space: nowrap; }
.strategy { font-size: 11px; padding: 1px 7px; margin-right: 4px; }
.row-toggle { background: none; border: 0; padding: 0; font: inherit; color: var(--vg-action); cursor: pointer; text-align: left; }
.row-toggle:hover, .row-toggle:focus-visible { text-decoration: underline; }
.row.open td { background: color-mix(in srgb, var(--vg-hue-blue) 5%, transparent); }
.detail td { padding-top: 4px; }
.detail-body { display: grid; gap: 10px; padding: 6px 2px 10px; }
.detail-head { display: flex; flex-wrap: wrap; align-items: end; justify-content: space-between; gap: 12px; }
.path { font-size: 12.5px; color: var(--vg-text-secondary); margin: 0; overflow-wrap: anywhere; }
.request { display: flex; flex-wrap: wrap; align-items: end; gap: 10px; }
.request .form-field { min-width: min(260px, 100%); }
.timeline { list-style: none; margin: 0; padding: 0; display: grid; gap: 4px; }
.timeline li { display: grid; grid-template-columns: 56px 130px minmax(0, 1fr) auto; gap: 12px; align-items: baseline; padding: 6px 10px; border-radius: 8px; background: var(--vg-well); font-size: 13px; }
.timeline li.unrecorded { background: color-mix(in srgb, var(--vg-hue-amber) 6%, transparent); }
.timeline .ver { font-weight: 650; }
.timeline .fp { font-size: 12.5px; }
.timeline .when { color: var(--vg-text-secondary); font-size: 12px; white-space: nowrap; }
code { font-family: var(--font-mono); font-size: 0.92em; }
@media (max-width: 720px) {
  .timeline li { grid-template-columns: 48px minmax(0, 1fr); }
  .timeline .what, .timeline .when { grid-column: 2; }
}
</style>
