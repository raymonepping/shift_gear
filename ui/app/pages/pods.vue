<script setup lang="ts">
import type { PodsResponse, PodCard, PodIndicator } from '../../shared/types'

useHead({ title: 'Pods · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const { data, status, refresh } = await useFetch<PodsResponse>('/api/v1/pods', { server: false, lazy: true })
const checking = computed(() => status.value === 'pending')
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => refresh(), 15_000) })
onBeforeUnmount(() => clearInterval(timer))

const pods = computed(() => data.value?.pods ?? [])
const reachable = computed(() => pods.value.filter(p => p.reachable).length)

const selected = ref<{ pod: string; indicator: string } | null>(null)
function toggleIndicator(pod: PodCard, indicator: PodIndicator) {
  selected.value = selected.value?.pod === pod.name && selected.value?.indicator === indicator.kind ? null : { pod: pod.name, indicator: indicator.kind }
}
function isSelected(pod: PodCard, indicator: PodIndicator): boolean {
  return selected.value?.pod === pod.name && selected.value?.indicator === indicator.kind
}

function roleBadgeClass(role: string): string {
  if (role.includes('SEAL VAULT')) return 'seal'
  if (role.includes('AGENT')) return 'agent'
  return ''
}

function statusTone(status: string): 'state-pass' | 'state-fail' | 'state-warn' | 'state-unknown' {
  if (status === 'pass') return 'state-pass'
  if (status === 'fail') return 'state-fail'
  if (status === 'warn') return 'state-warn'
  return 'state-unknown'
}
</script>

<template>
  <div>
    <section class="vg-hero fleet-hero" aria-labelledby="pods-title">
      <div class="hero-head">
        <div>
          <p class="eyebrow">OpenShift · four indicators per pod</p>
          <h1 id="pods-title">Pods</h1>
          <p>Every pod Shift Gear manages. Open any indicator to see the evidence behind it.</p>
        </div>
        <button class="secondary-button" type="button" :disabled="checking" @click="refresh()">
          <svg class="button-icon" :class="{ spinning: checking }" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5" /></svg>
          {{ checking ? 'Checking…' : 'Refresh' }}
        </button>
      </div>
      <p v-if="data" class="hero-status" :class="{ attention: reachable < pods.length }" role="status">
        {{ pods.length }} shift-gear pods · {{ reachable }} reachable · {{ reachable === pods.length ? 'all green' : `${pods.length - reachable} unreachable` }}
      </p>
    </section>

    <div v-if="checking && !data" class="skeleton" aria-label="Loading"><div v-for="i in 6" :key="i" /></div>

    <div v-if="pods.length" class="instance-grid" role="list">
      <article v-for="pod in pods" :key="pod.name" class="vg-card instance-card" role="listitem" :aria-label="pod.name">
        <div class="card-head">
          <div class="card-name">
            <strong>{{ pod.name }}</strong>
            <small>{{ pod.namespace }} · {{ pod.podIP ?? 'no IP' }}</small>
          </div>
          <span class="state-chip" :class="pod.reachable ? 'running' : 'deleted'">
            <i aria-hidden="true" />{{ pod.reachable ? 'Reachable' : 'Unreachable' }}
          </span>
        </div>
        <div class="card-meta">
          <span class="role-chip" :class="roleBadgeClass(pod.role)">{{ pod.role }}</span>
        </div>
        <!-- Four indicators 2×2 -->
        <div class="posture-flow" role="group" :aria-label="`${pod.name} indicators`">
          <button
            v-for="indicator in pod.indicators"
            :key="indicator.kind"
            type="button"
            class="posture-pill"
            :class="`tone-${indicator.status === 'pass' ? 'positive' : indicator.status === 'fail' ? 'critical' : indicator.status === 'warn' ? 'warning' : 'neutral'}`"
            :aria-expanded="isSelected(pod, indicator)"
            :aria-controls="`evidence-${pod.name}-${indicator.kind}`"
            @click="toggleIndicator(pod, indicator)"
          >
            <span class="glyph" :class="statusTone(indicator.status)" aria-hidden="true">
              <svg v-if="indicator.status === 'pass'" viewBox="0 0 14 14" fill="currentColor"><path d="M2 7.5l3.5 3.5L12 4"/></svg>
              <svg v-else-if="indicator.status === 'fail'" viewBox="0 0 14 14" fill="currentColor"><path d="M3 3l8 8M11 3l-8 8"/></svg>
              <svg v-else viewBox="0 0 14 14" fill="currentColor"><circle cx="7" cy="7" r="5"/></svg>
            </span>
            <span class="copy">
              <span class="kind">{{ indicator.label }}</span>
              <span class="value">{{ indicator.detail || '—' }}</span>
            </span>
          </button>
        </div>
        <!-- Evidence panel (expands when indicator is selected) -->
        <div
          v-if="pod.indicators.some(i => isSelected(pod, i))"
          :id="`evidence-${pod.name}-${pod.indicators.find(i => isSelected(pod, i))?.kind}`"
          class="evidence-detail"
        >
          <template v-for="indicator in pod.indicators" :key="indicator.kind">
            <div v-if="isSelected(pod, indicator)">
              <p class="evidence-source">{{ indicator.evidenceSource }}</p>
              <p class="evidence-detail-text">{{ indicator.detail || 'not reported' }}</p>
            </div>
          </template>
        </div>
        <!-- Resource summary -->
        <div class="resource-row">
          <span v-if="pod.resources.cpuRequest"><b>CPU</b> {{ pod.resources.cpuRequest }}</span>
          <span v-if="pod.resources.memRequest"><b>MEM</b> {{ pod.resources.memRequest }}</span>
          <span v-if="pod.resources.pvcSize"><b>PVC</b> {{ pod.resources.pvcSize }}</span>
        </div>
      </article>
    </div>
  </div>
</template>

<style scoped>
.state-chip { display: inline-flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 600; color: var(--vg-text-muted); }
.state-chip i { width: 7px; height: 7px; border-radius: 50%; background: var(--vg-text-dim); flex-shrink: 0; }
.state-chip.running { color: var(--vg-healthy); }
.state-chip.running i { background: var(--vg-healthy); box-shadow: 0 0 6px color-mix(in srgb, var(--vg-hue-green) 60%, transparent); }
.state-chip.deleted { color: var(--vg-critical); }
.state-chip.deleted i { background: var(--vg-critical); }
.evidence-detail { padding: 8px 10px; border-radius: 8px; background: var(--vg-well); border: 1px solid var(--vg-border-subtle); font-size: 12px; }
.evidence-source { margin: 0; color: var(--vg-text-muted); font-family: var(--font-mono); font-size: 11px; }
.evidence-detail-text { margin: 4px 0 0; color: var(--vg-text-secondary); }
.resource-row { display: flex; gap: 12px; flex-wrap: wrap; font-size: 12px; color: var(--vg-text-muted); font-variant-numeric: tabular-nums; margin-top: auto; }
.resource-row b { color: var(--vg-text-secondary); font-weight: 650; }
</style>
