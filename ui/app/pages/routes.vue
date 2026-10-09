<script setup lang="ts">
import type { RoutesResponse } from '../../shared/types'

useHead({ title: 'Routes · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const { data, status, refresh } = await useFetch<RoutesResponse>('/api/v1/routes', { server: false, lazy: true })
const checking = computed(() => status.value === 'pending')
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => refresh(), 10_000) })
onBeforeUnmount(() => clearInterval(timer))

const allHealthy = computed(() =>
  data.value?.routes.every(r => r.backends.every(b => b.ready)) ?? false,
)

function backendClass(backend: { ready: boolean; role: string }): string {
  if (!backend.ready) return 'state-fail'
  return backend.role === 'leader' ? 'state-pass' : 'door-chip state-unknown'
}
</script>

<template>
  <div>
    <section class="vg-hero fleet-hero" aria-labelledby="routes-title">
      <div class="hero-head">
        <div>
          <p class="eyebrow">OpenShift Router · TLS in, verified TLS out</p>
          <h1 id="routes-title">Routes</h1>
          <p>Every OpenShift Route Shift Gear exposes. Passthrough Routes hand TLS straight to the pod; re-encrypt Routes verify the backend's certificate. Vault writes always reach the active node.</p>
        </div>
        <button class="secondary-button" type="button" :disabled="checking" @click="refresh()">
          <svg class="button-icon" :class="{ spinning: checking }" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5" /></svg>
          {{ checking ? 'Checking…' : 'Refresh' }}
        </button>
      </div>
      <p v-if="data" class="hero-status" :class="{ attention: !allHealthy }" role="status">
        {{ data.routes.length }} routes · {{ allHealthy ? 'every route has a healthy backend' : 'some backends unavailable' }}
      </p>
    </section>

    <div v-if="checking && !data" class="skeleton" aria-label="Loading"><div /><div /><div /></div>

    <section v-if="data" class="panel vg-glass" aria-labelledby="routes-list-title">
      <div class="panel-head">
        <h2 id="routes-list-title">Entry points</h2>
        <span class="source-tag">{{ data.observedAt ? new Date(data.observedAt).toLocaleTimeString() : '—' }}</span>
      </div>
      <div class="door-list" role="list">
        <div v-for="route in data.routes" :key="route.name" class="door-row" role="listitem">
          <div class="door-name">
            <strong>{{ route.label }}</strong>
            <a :href="route.url" target="_blank" rel="noopener noreferrer" class="route-url">{{ route.url }}</a>
            <div class="route-meta">
              <span class="tls-badge" :class="route.tlsTermination.toLowerCase().replace('-', '')">{{ route.tlsTermination }}</span>
              <span class="route-ns mono">{{ route.namespace }}</span>
            </div>
          </div>
          <div class="door-servers" role="list" :aria-label="`Backends for ${route.label}`">
            <span
              v-for="backend in route.backends"
              :key="backend.podName"
              class="door-chip-backend"
              :class="backendClass(backend)"
              role="listitem"
            >
              <i aria-hidden="true" />
              {{ backend.podName }}
              <span v-if="backend.role === 'leader'" class="leader-tag" aria-label="leader">★</span>
            </span>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>

<style scoped>
.route-url { font-size: 11.5px; overflow-wrap: anywhere; color: var(--vg-action-bright); }
.route-meta { display: flex; align-items: center; gap: 8px; margin-top: 4px; flex-wrap: wrap; }
.route-ns { font-size: 11px; color: var(--vg-text-muted); }
.leader-tag { font-size: 9px; color: var(--vg-governance); margin-left: 2px; }
.door-chip-backend { display: inline-flex; align-items: center; gap: 5px; padding: 2px 9px; border-radius: 100px; font-family: var(--font-mono); font-size: 11.5px; font-weight: 600; border: 1px solid transparent; }
.door-chip-backend i { width: 6px; height: 6px; border-radius: 50%; background: currentColor; }
.door-chip-backend.state-pass { background: var(--vg-healthy-bg); color: var(--vg-healthy); border-color: color-mix(in srgb, var(--vg-hue-green) 22%, transparent); }
.door-chip-backend.state-fail { background: var(--vg-critical-bg); color: var(--vg-critical); border-color: color-mix(in srgb, var(--vg-hue-red) 22%, transparent); }
.door-chip-backend.state-unknown { background: color-mix(in srgb, var(--vg-hue-slate) 10%, transparent); color: var(--vg-text-dim); border-color: color-mix(in srgb, var(--vg-hue-slate) 20%, transparent); }
</style>
