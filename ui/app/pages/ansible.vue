<script setup lang="ts">
import type { AnsibleValidateResponse, AnsibleConvergenceResponse } from '../../shared/types'

useHead({ title: 'Ansible · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const { data: validate, status: vStatus, refresh: refreshValidate } = await useFetch<AnsibleValidateResponse>('/api/v1/ansible/validate', { server: false, lazy: true })
const { data: convergence } = await useFetch<AnsibleConvergenceResponse>('/api/v1/ansible/convergence', { server: false, lazy: true })

const checkingV = computed(() => vStatus.value === 'pending')
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => refreshValidate(), 60_000) })
onBeforeUnmount(() => clearInterval(timer))

const { session } = useAuth()
const canRun = computed(() => session.value?.roles.isOperator || session.value?.roles.isAdmin || false)

const running = ref(false)
const runError = ref<string | null>(null)

async function runValidate() {
  running.value = true
  runError.value = null
  try {
    await $fetch('/api/v1/ansible/validate/run', { method: 'POST' })
    await new Promise(r => setTimeout(r, 5_000))
    await refreshValidate()
  } catch (e) {
    runError.value = (e as { message?: string }).message ?? 'unknown error'
  } finally {
    running.value = false
  }
}

function statusIcon(result: string): string {
  if (result === 'pass') return '✓'
  if (result === 'fail') return '✗'
  return '⚠'
}

function rowTone(result: string): string {
  if (result === 'pass') return 'row-pass'
  if (result === 'fail') return 'row-fail'
  return 'row-warn'
}

const convergenceState = computed(() => {
  const c = convergence.value
  if (!c) return { tone: 'unknown', text: 'not reported' }
  if (!c.appliedDigest) return { tone: 'unknown', text: 'never converged' }
  if (c.converged) return { tone: 'pass', text: `converged (${c.appliedDigest.slice(0, 12)}…)` }
  return { tone: 'warn', text: `drift detected — applied ${c.appliedDigest.slice(0, 12)}…, current ${c.currentDigest?.slice(0, 12) ?? '?'}…` }
})
</script>

<template>
  <div>
    <section class="vg-hero fleet-hero" aria-labelledby="ansible-title">
      <div class="hero-head">
        <div>
          <p class="eyebrow">Ansible · observe-only console</p>
          <h1 id="ansible-title">Ansible</h1>
          <p>The last <code>make validate</code> output and the automation convergence digest. Ansible runs on the operator's machine, never from this console — the validate button triggers an API that calls back to the running Ansible phase.</p>
        </div>
      </div>
    </section>

    <!-- Convergence -->
    <section class="sg-layer-panel sg-layer-panel--ansible panel" aria-labelledby="conv-title">
      <div class="panel-head">
        <div>
          <p class="sg-provenance-badge">Ansible</p>
          <h2 id="conv-title">Convergence</h2>
        </div>
      </div>
      <div v-if="convergence" class="conv-row">
        <span class="door-chip" :class="convergenceState.tone === 'pass' ? 'state-pass' : convergenceState.tone === 'warn' ? 'state-warn' : 'state-unknown'">
          <i aria-hidden="true" />{{ convergenceState.text }}
        </span>
        <span v-if="convergence.lastRun" class="conv-when">last run: {{ new Date(convergence.lastRun).toLocaleString() }}</span>
      </div>
    </section>

    <!-- Validate results -->
    <section class="sg-layer-panel sg-layer-panel--ansible panel" aria-labelledby="validate-title">
      <div class="panel-head">
        <div>
          <p class="sg-provenance-badge">Ansible</p>
          <h2 id="validate-title">Validate results</h2>
          <p v-if="validate?.generatedAt">Generated {{ new Date(validate.generatedAt).toLocaleString() }}</p>
        </div>
        <div class="validate-actions">
          <button v-if="canRun" type="button" class="secondary-button" :disabled="running" @click="runValidate()">
            <svg v-if="running" class="button-icon spinning" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5" /></svg>
            {{ running ? 'Running…' : 'Run validate now' }}
          </button>
          <button type="button" class="secondary-button" :disabled="checkingV" @click="refreshValidate()">Refresh</button>
        </div>
      </div>
      <p v-if="runError" class="inline-notice error" role="alert">{{ runError }}</p>
      <div v-if="validate" class="validate-summary">
        <span class="door-chip state-pass"><i aria-hidden="true" />{{ validate.passCount }} pass</span>
        <span v-if="validate.warnCount" class="door-chip state-warn"><i aria-hidden="true" />{{ validate.warnCount }} warn</span>
        <span v-if="validate.failCount" class="door-chip state-fail"><i aria-hidden="true" />{{ validate.failCount }} fail</span>
      </div>
      <div v-if="validate?.rows.length" class="validate-list" role="list">
        <div v-for="row in validate.rows" :key="row.id" class="validate-row" :class="rowTone(row.result)" role="listitem">
          <span class="row-icon" aria-hidden="true">{{ statusIcon(row.result) }}</span>
          <div class="row-body">
            <span class="row-label">{{ row.label }}</span>
            <span v-if="row.detail" class="row-detail">{{ row.detail }}</span>
          </div>
        </div>
      </div>
      <p v-else-if="!validate" class="state-empty">No validate results — run <code>make validate</code>.</p>
    </section>
  </div>
</template>

<style scoped>
.conv-row { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.conv-when { font-size: 12px; color: var(--vg-text-muted); }
.validate-actions { display: flex; gap: 8px; }
.validate-summary { display: flex; align-items: center; gap: 8px; margin-bottom: 12px; flex-wrap: wrap; }
.validate-list { display: grid; gap: 6px; }
.validate-row { display: flex; gap: 10px; padding: 8px 10px; border-radius: 8px; border: 1px solid var(--vg-border-subtle); background: var(--vg-well); font-size: 13px; align-items: flex-start; }
.validate-row.row-pass { border-color: color-mix(in srgb, var(--vg-hue-green) 20%, transparent); }
.validate-row.row-fail { border-color: color-mix(in srgb, var(--vg-hue-red) 22%, transparent); background: color-mix(in srgb, var(--vg-hue-red) 4%, transparent); }
.validate-row.row-warn { border-color: color-mix(in srgb, var(--vg-hue-amber) 22%, transparent); }
.row-icon { font-size: 14px; font-weight: 700; flex-shrink: 0; }
.row-pass .row-icon { color: var(--vg-healthy); }
.row-fail .row-icon { color: var(--vg-critical); }
.row-warn .row-icon { color: var(--vg-pending); }
.row-body { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.row-label { font-weight: 600; color: var(--vg-text-primary); }
.row-detail { font-size: 12px; color: var(--vg-text-muted); overflow-wrap: anywhere; }
</style>
