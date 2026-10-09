<script setup lang="ts">
import type { LayerGate, LayerRow, LayersResponse } from '../../shared/types'

useHead({ title: 'Layers · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const { data, status, refresh } = await useFetch<LayersResponse>('/api/layers', { server: false, lazy: true })
const checking = computed(() => status.value === 'pending')
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => refresh(), 30_000) })
onBeforeUnmount(() => clearInterval(timer))

const phases = computed(() => data.value?.phases ?? [])
const gates = computed(() => data.value?.gates ?? [])
const selected = ref<string | null>(null)

const ago = (at: string | null | undefined): string => {
  if (!at) return 'never'
  const minutes = Math.max(0, Math.round((Date.now() - new Date(at).getTime()) / 60_000))
  if (minutes < 1) return 'just now'
  if (minutes < 90) return `${minutes} min ago`
  const hours = Math.round(minutes / 60)
  return hours < 48 ? `${hours} h ago` : `${Math.round(hours / 24)} d ago`
}

type Tone = 'state-pass' | 'state-warn' | 'state-fail' | 'state-unknown'
interface Verdict { tone: Tone; text: string }

function verdict(row: LayerRow): Verdict {
  if (row.tool === 'terraform') {
    switch (row.lastPlan?.result) {
      case 'clean': return { tone: 'state-pass', text: 'plan empty' }
      case 'drift': return { tone: 'state-warn', text: 'drift' }
      case 'error': return { tone: 'state-fail', text: 'plan failed' }
      default: return { tone: 'state-unknown', text: 'not checked' }
    }
  }
  if (!row.lastRun) return { tone: 'state-unknown', text: 'never run' }
  if (row.lastRun.failed > 0) return { tone: 'state-fail', text: `${row.lastRun.failed} failed` }
  if (row.lastRun.changed === 0) return { tone: 'state-pass', text: 'changed=0' }
  return row.allowedChanges
    ? { tone: 'state-pass', text: `changed=${row.lastRun.changed} · allow-listed` }
    : { tone: 'state-warn', text: `changed=${row.lastRun.changed}` }
}

function gateVerdict(gate: LayerGate): Verdict {
  return gate.result === 'pass'
    ? { tone: 'state-pass', text: 'pass' }
    : gate.result === 'fail'
      ? { tone: 'state-fail', text: 'fail' }
      : { tone: 'state-unknown', text: 'unknown' }
}

const gateLabel: Record<string, string> = {
  'idempotency': 'Idempotency',
  'drift': 'Drift',
  'secret-scan': 'Secret scan',
  'validation': 'Validation',
}

const digestState = computed(() => {
  const d = data.value?.digest
  if (!d?.applied || !d.current) return { tone: 'unknown', text: 'automation digest unavailable' }
  return d.applied === d.current
    ? { tone: 'pass', text: `automation unchanged since the last make lab (${d.current.slice(0, 12)}…)` }
    : { tone: 'warn', text: `automation changed — applied ${d.applied.slice(0, 12)}…, now ${d.current.slice(0, 12)}…` }
})

const allGreen = computed(() =>
  digestState.value.tone === 'pass'
  && gates.value.length > 0
  && gates.value.every(g => g.result === 'pass')
  && phases.value.every(r => verdict(r).tone === 'state-pass'),
)

const counts = computed(() => ({
  terraform: phases.value.filter(r => r.tool === 'terraform').length,
  ansible: phases.value.filter(r => r.tool === 'ansible').length,
}))

function evidenceSource(row: LayerRow): string {
  return row.tool === 'terraform'
    ? `terraform/${row.phase} — state resource count, last apply and last plan`
    : `ansible/${row.phase}.yml — recap counts from the sg_stats callback`
}
</script>

<template>
  <div>
    <section class="vg-hero fleet-hero" aria-labelledby="layers-title">
      <div class="hero-head">
        <div>
          <p class="eyebrow">scripts/phases.txt · one phase list, two tools</p>
          <h1 id="layers-title">Terraform builds it · Ansible decorates it</h1>
          <p>Every phase of <code class="mono">make lab</code> in order, with the evidence each tool leaves behind, and the gates that must be green before the system counts as converged.</p>
        </div>
        <button class="secondary-button" type="button" :disabled="checking" @click="refresh()">
          <svg class="button-icon" :class="{ spinning: checking }" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5" /></svg>
          {{ checking ? 'Checking…' : 'Refresh' }}
        </button>
      </div>
      <p v-if="data?.readable" class="hero-status" :class="{ attention: !allGreen }" role="status">
        {{ counts.terraform }} Terraform · {{ counts.ansible }} Ansible phases · {{ allGreen ? 'every phase and gate green' : 'something needs attention' }} · evidence {{ ago(data.generatedAt) }}
      </p>
      <p v-if="data?.readable" class="hero-status" :class="{ attention: digestState.tone !== 'pass' }">
        {{ digestState.text }}
      </p>
    </section>

    <div v-if="!data && checking" class="skeleton" aria-label="Loading"><div /><div /></div>

    <section v-else-if="data && !data.readable" class="panel vg-glass" role="alert">
      <h2 class="panel-head"><div>No layer evidence yet</div></h2>
      <p class="state-empty"><code>.build/layers.json</code> is written at the end of a successful <code>make lab</code> or <code>make layers</code>.</p>
    </section>

    <template v-else-if="data">
      <!-- Gates -->
      <section class="panel vg-glass" aria-labelledby="gates-title">
        <div class="panel-head">
          <div><h2 id="gates-title">Gates</h2><p>What <code>make lab</code> requires before it writes the convergence stamp.</p></div>
          <span class="source-tag">.build/gates/</span>
        </div>
        <ul class="gate-strip" role="list">
          <li v-for="gate in gates" :key="gate.name" class="gate">
            <span class="gate-name">{{ gateLabel[gate.name] }}</span>
            <span class="door-chip" :class="gateVerdict(gate).tone"><i aria-hidden="true" />{{ gateVerdict(gate).text }}</span>
            <span class="gate-age">{{ ago(gate.at) }}</span>
            <span class="gate-source">{{ gate.script }}</span>
          </li>
        </ul>
      </section>

      <!-- Phases -->
      <section class="panel vg-glass" aria-labelledby="phases-title">
        <div class="panel-head">
          <div><h2 id="phases-title">Phases</h2><p>In the order <code>make lab</code> runs them. Select a phase to see where its evidence comes from.</p></div>
          <span class="source-tag">.build/layers.json</span>
        </div>
        <ol class="layer-list">
          <li v-for="(row, index) in phases" :key="row.phase">
            <button
              type="button"
              class="layer-row"
              :aria-expanded="selected === row.phase"
              :aria-controls="`layer-${row.phase}`"
              @click="selected = selected === row.phase ? null : row.phase"
            >
              <span class="layer-index">{{ index + 1 }}</span>
              <span class="tool-tag" :class="row.tool">{{ row.tool === 'terraform' ? 'Terraform' : 'Ansible' }}</span>
              <span class="layer-name mono">{{ row.phase }}</span>
              <span class="layer-fact">
                <template v-if="row.tool === 'terraform'">{{ row.resources ?? '?' }} resources · applied {{ ago(row.lastApply?.at) }}</template>
                <template v-else>last run {{ ago(row.lastRun?.at) }}</template>
              </span>
              <span class="door-chip" :class="verdict(row).tone"><i aria-hidden="true" />{{ verdict(row).text }}</span>
            </button>
            <div v-if="selected === row.phase" :id="`layer-${row.phase}`" class="layer-detail">
              <p><strong>Source</strong> {{ evidenceSource(row) }}</p>
              <p v-if="row.tool === 'terraform'"><strong>Last plan</strong> {{ row.lastPlan ? `${row.lastPlan.result}, ${ago(row.lastPlan.at)}` : 'never checked — run make drift' }}</p>
              <p v-if="row.allowedChanges"><strong>Allowed changes</strong> {{ row.allowedChanges }}</p>
              <p v-if="row.tool === 'ansible'"><strong>Last check mode</strong> {{ row.lastCheck ? `changed=${row.lastCheck.changed}, ${ago(row.lastCheck.at)}` : 'never — run make drift' }}</p>
            </div>
          </li>
        </ol>
      </section>
    </template>
  </div>
</template>

<style scoped>
.gate-strip { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 10px; }
.gate { display: grid; grid-template-columns: 1fr auto; gap: 4px 10px; padding: 12px 14px; border-radius: 12px; background: var(--vg-well); border: 1px solid var(--vg-border-subtle); }
.gate-name { font-weight: 680; color: var(--vg-text-primary); }
.gate-age { grid-column: 1 / -1; font-size: 12px; color: var(--vg-text-muted); font-variant-numeric: tabular-nums; }
.gate-source { grid-column: 1 / -1; font-family: var(--font-mono); font-size: 11.5px; color: var(--vg-text-muted); }
.layer-list { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
.layer-row { width: 100%; display: grid; grid-template-columns: 28px 92px minmax(90px, 140px) 1fr auto; align-items: center; gap: 10px; padding: 10px 12px; border-radius: 12px; border: 1px solid var(--vg-border-subtle); background: var(--vg-well); font: inherit; color: var(--vg-text-secondary); text-align: left; cursor: pointer; transition: background 180ms cubic-bezier(0.16,1,0.3,1); }
.layer-row:hover { background: var(--vg-hover); }
.layer-row:focus-visible { outline: 2px solid var(--vg-focus); outline-offset: 2px; }
.layer-index { font-variant-numeric: tabular-nums; color: var(--vg-text-muted); font-size: 12px; }
.layer-name { color: var(--vg-text-primary); font-weight: 600; }
.layer-fact { font-size: 12.5px; color: var(--vg-text-muted); font-variant-numeric: tabular-nums; }
.tool-tag { justify-self: start; padding: 2px 9px; border-radius: 100px; font-size: 11.5px; font-weight: 680; border: 1px solid transparent; }
.tool-tag.terraform { color: var(--vg-hue-indigo); background: color-mix(in srgb, var(--vg-hue-indigo) 10%, transparent); border-color: color-mix(in srgb, var(--vg-hue-indigo) 28%, transparent); }
.tool-tag.ansible { color: var(--vg-text-secondary); background: color-mix(in srgb, var(--vg-hue-slate) 10%, transparent); border-color: color-mix(in srgb, var(--vg-hue-slate) 28%, transparent); }
.layer-row > .door-chip { white-space: nowrap; }
.layer-detail { margin: 4px 0 4px 38px; padding: 10px 12px; border-radius: 10px; background: var(--vg-well); font-size: 12.5px; color: var(--vg-text-secondary); }
.layer-detail p { margin: 2px 0; }
.layer-detail strong { color: var(--vg-text-primary); margin-right: 6px; }
@media (max-width: 720px) {
  .layer-row { grid-template-columns: 24px auto 1fr; grid-template-areas: "i t n" "f f c"; }
  .layer-index { grid-area: i; }
  .tool-tag { grid-area: t; }
  .layer-name { grid-area: n; }
  .layer-fact { grid-area: f; }
  .layer-row > .door-chip { grid-area: c; justify-self: end; }
}
</style>
