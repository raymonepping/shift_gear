<script setup lang="ts">
import type { ClusterResponse } from '../../shared/types'

useHead({ title: 'Cluster · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const { data, status, refresh, error } = await useFetch<ClusterResponse>('/api/v1/cluster', { server: false, lazy: true })
const checking = computed(() => status.value === 'pending')
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => refresh(), 5_000) })
onBeforeUnmount(() => clearInterval(timer))

function ttlLabel(seconds: number | null) {
  if (seconds == null) return '—'
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}
</script>

<template>
  <div class="sg-cluster">
    <section class="vg-hero">
      <h2 class="sg-h">Seal chain and cluster</h2>
      <p class="sg-sub">
        The seal Vault is the root of trust. The seal agent holds its AppRole credential and
        unseals the main cluster via Transit auto-unseal. Kill the leader — leadership moves.
        The cluster keeps serving.
      </p>
    </section>

    <SourceState :status="status" :has-data="!!data" :code="error?.statusCode" label="Cluster observations" @retry="refresh()" />

    <SealChainStatus />

    <div v-if="data" class="vg-grid-3">
      <div class="vg-tile" :class="data.vaultCluster.unsealed === data.vaultCluster.total ? 'vg-tile--good' : 'vg-tile--bad'">
        <span class="vg-tile__label">Main cluster · snapshot</span>
        <span class="vg-tile__value">{{ data.vaultCluster.unsealed }}/{{ data.vaultCluster.total }}</span>
        <span class="vg-tile__sub">unsealed · leader {{ data.vaultCluster.leader ?? 'none' }}</span>
      </div>
      <div class="vg-tile vg-tile--gold">
        <span class="vg-tile__label">Licence expiry</span>
        <span class="vg-tile__value sg-lic">{{ data.licenceExpiry ? new Date(data.licenceExpiry).toLocaleDateString() : '—' }}</span>
        <span class="vg-tile__sub">Vault Enterprise</span>
      </div>
      <div class="vg-tile" :class="data.vsoCsvStatus === 'Succeeded' ? 'vg-tile--good' : 'vg-tile--warn'">
        <span class="vg-tile__label">VSO CSV status</span>
        <span class="vg-tile__value">{{ data.vsoCsvStatus }}</span>
        <span class="vg-tile__sub">Vault Secrets Operator</span>
      </div>
    </div>

    <div v-if="data" class="vg-grid-2">
      <div class="vg-glass sg-panel">
        <div class="vg-section-header"><h2 class="vg-section-title">Seal agent</h2></div>
        <dl class="sg-dl">
          <dt>Token TTL</dt><dd>{{ ttlLabel(data.sealAgent.tokenTtl) }}</dd>
          <dt>Secret ID age</dt><dd>{{ data.sealAgent.secretIdAge ?? '—' }}</dd>
          <dt>Last rotation</dt><dd>{{ data.sealAgent.lastRotation ? new Date(data.sealAgent.lastRotation).toLocaleString() : '—' }}</dd>
        </dl>
      </div>
      <div class="vg-glass sg-panel">
        <div class="vg-section-header"><h2 class="vg-section-title">Audit collector</h2></div>
        <dl class="sg-dl">
          <dt>Connections</dt><dd>{{ data.auditCollector.connections }}</dd>
          <dt>Records received</dt><dd>{{ data.auditCollector.received }}</dd>
        </dl>
      </div>
    </div>

    <div v-if="checking && !data" class="sg-loading" aria-live="polite">Loading cluster data…</div>
    <button class="sg-btn-refresh" :disabled="checking" @click="refresh()">
      <span :class="checking ? 'sg-spin' : ''">↻</span> Refresh now
    </button>
  </div>
</template>

<style scoped>
.sg-cluster { display: grid; gap: 18px; max-width: 1360px; margin: 0 auto; }
.sg-h { margin: 0 0 6px; font-size: 24px; font-weight: 800; letter-spacing: -0.025em; }
.sg-sub { margin: 0; color: var(--vg-text-secondary); max-width: 72ch; }
.sg-panel { padding: 16px 20px; display: grid; gap: 12px; }
.sg-obs { font-size: 12px; color: var(--vg-text-muted); }
.sg-chain { display: flex; align-items: flex-start; gap: 10px; flex-wrap: wrap; }
.sg-chain-arrow { color: var(--vg-text-muted); font-size: 20px; margin-top: 22px; flex-shrink: 0; }
.sg-chain-node { display: grid; gap: 4px; justify-items: start; padding: 12px 14px; border-radius: 12px; background: var(--vg-well); box-shadow: inset 0 0 0 1px var(--vg-border-subtle); font-size: 12.5px; min-width: 156px; }
.sg-chain-node strong { font-size: 14px; }
.sg-chain-node--sm { min-width: 130px; }
.sg-chain-node[data-role='leader'] { box-shadow: inset 0 0 0 2px color-mix(in srgb, var(--sg-layer-tf) 50%, transparent); }
.sg-chain-nodes { display: flex; gap: 8px; flex-wrap: wrap; }
.sg-chain-icon { width: 18px; height: 18px; margin-bottom: 2px; }
.sg-chain-detail { font-size: 11.5px; color: var(--vg-text-muted); }
.sg-mono { font-family: var(--vg-font-mono); }
.sg-lic { font-size: 22px; }
.sg-dl { display: grid; grid-template-columns: max-content 1fr; gap: 6px 16px; font-size: 13px; margin: 0; }
.sg-dl dt { color: var(--vg-text-muted); }
.sg-dl dd { margin: 0; font-weight: 600; }
.sg-loading { text-align: center; color: var(--vg-text-muted); font-size: 13px; padding: 24px; }
.sg-btn-refresh { justify-self: end; font-size: 13px; padding: 6px 14px; border-radius: 8px; border: 1px solid var(--vg-border); background: transparent; color: var(--vg-text-secondary); cursor: pointer; }
.sg-btn-refresh:hover { background: var(--vg-well); }
.sg-btn-refresh:disabled { opacity: .5; cursor: default; }
.sg-spin { display: inline-block; animation: spin 1s linear infinite; }
@media (max-width: 640px) {
  .sg-chain-node, .sg-chain-node--sm { min-width: 0; max-width: 100%; overflow-wrap: anywhere; }
  .sg-dl { grid-template-columns: minmax(0, 1fr); }
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
