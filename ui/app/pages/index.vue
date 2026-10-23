<script setup lang="ts">
import type { FleetResponse } from '../../shared/types'

useHead({ title: 'Fleet · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const { fleet, checking, failed, refresh } = useFleet()
const { data: fleetData, status: fleetStatus } = await useFetch<FleetResponse>('/api/v1/fleet', { server: false, lazy: true })

const f = computed(() => fleet.value ?? fleetData.value)
const loading = computed(() => fleetStatus.value === 'pending' && !f.value)
const observed = computed(() => f.value?.observedAt ? new Date(f.value.observedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '—')

function tileClass(tone: string) {
  return tone === 'good' ? 'is-good' : tone === 'warn' ? 'is-warn' : tone === 'bad' ? 'is-bad' : ''
}
</script>

<template>
  <div>
    <section class="vg-hero fleet-hero" aria-labelledby="fleet-title">
      <div class="hero-head">
        <div>
          <p class="eyebrow">Vault Enterprise · OpenShift · Terraform + Ansible</p>
          <h1 id="fleet-title">Provisioned, converged, sealed by design</h1>
          <p>Terraform builds the house and the Vault structure. Ansible decorates it. The Vault Secrets Operator delivers secrets to workloads. No Vault pod holds a seal token.</p>
          <p class="observe-notice"><strong>Published observations:</strong> lifecycle actions run from the host console. Approved secret rotation is available to operators.</p>
        </div>
        <div class="flex items-center gap-3">
          <span class="observed">Snapshot observed {{ observed }}</span>
          <button class="secondary-button" type="button" :disabled="checking" @click="refresh()">
            <svg class="button-icon" :class="{ spinning: checking }" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5" /></svg>
            {{ checking ? 'Checking…' : 'Refresh' }}
          </button>
        </div>
      </div>
      <div v-if="f?.tiles" class="hero-tiles">
        <div v-for="tile in f.tiles" :key="tile.label" class="vg-tile">
          <span class="vg-tile__label">{{ tile.label }}</span>
          <span class="vg-tile__value" :class="tileClass(tile.tone)">{{ tile.value }}</span>
          <span class="vg-tile__sub">{{ tile.sub }}</span>
          <span class="tile-source sr-only">{{ tile.source }}</span>
        </div>
      </div>
      <div v-if="loading" class="hero-tiles" aria-label="Loading">
        <div v-for="i in 5" :key="i" class="vg-tile" style="opacity:0.5"><span class="vg-tile__value">—</span></div>
      </div>
    </section>

    <section v-if="failed && !f" class="notice-panel vg-glass is-error" role="alert">
      <div class="grow"><h2>Control plane unreachable</h2><p>The API did not answer. Check <code>make vso-status</code>.</p></div>
      <button class="secondary-button" type="button" @click="refresh()">Try again</button>
    </section>

    <SealChainStatus />

    <!-- Summary tiles -->
    <nav v-if="f" class="fleet-links" aria-label="Navigate to detail pages">
      <NuxtLink to="/pods" class="fleet-link vg-glass">
        <strong>Pods</strong>
        <span>{{ f.podSummary.total }} shift-gear pods · {{ f.podSummary.reachable }} reachable</span>
      </NuxtLink>
      <NuxtLink to="/operator" class="fleet-link vg-glass">
        <strong>Vault Operator</strong>
        <span>{{ f.operatorSummary.staticSecrets }} VaultStaticSecrets · {{ f.operatorSummary.dynamicSecrets }} VaultDynamicSecrets</span>
      </NuxtLink>
    </nav>
  </div>
</template>

<style scoped>
.notice-panel { display: flex; align-items: center; gap: 14px; padding: 16px 18px; margin-bottom: 20px; }
.notice-panel h2 { margin: 0; font-size: 15px; color: var(--vg-text-primary); }
.notice-panel p { margin: 2px 0 0; font-size: 12.5px; color: var(--vg-text-secondary); }
.notice-panel .grow { flex: 1; }
.notice-panel.is-error { border-color: color-mix(in srgb, var(--vg-hue-red) 30%, transparent); }
.observe-notice { font-size: 12.5px; color: var(--vg-text-muted); }
.observe-notice code { font-family: var(--font-mono); }
</style>
