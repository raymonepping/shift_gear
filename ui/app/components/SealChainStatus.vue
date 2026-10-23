<script setup lang="ts">
import { sealSourceNames, sourceFresh } from '../../shared/seal-chain'

const { data, now, failed, status, chain, refresh } = useRuntime()
const nodes = computed(() => sealSourceNames.map((name, index) => {
  const source = data.value?.sources.find(row => row.name === name)
  const fresh = !failed.value && sourceFresh(source, now.value)
  const value = source?.data
  const label = index === 1 ? (value?.available === true ? 'available' : 'unavailable')
    : value?.initialized !== true ? 'uninitialized' : value?.sealed === true ? 'sealed'
      : index === 0 ? 'unsealed' : value?.standby === false && value?.performanceStandby === false ? 'leader' : 'standby'
  const pass = fresh && (index === 1 ? value?.available === true : value?.initialized === true && value?.sealed === false)
  return { name: index < 2 ? name : name.replace('Vault member ', ''), resource: source?.resource,
    label: fresh ? label : 'not verified', tone: !fresh ? 'unknown' : pass ? 'healthy' : 'critical',
    role: index > 1 && fresh ? label : undefined, at: source?.observedAt }
}))
const unsealed = computed(() => nodes.value.slice(2).filter(node => node.tone === 'healthy').length)
</script>

<template>
  <section class="vg-glass sg-panel live-seal-chain" aria-label="Seal chain">
    <div class="vg-section-header">
      <h2 class="vg-section-title">Seal chain</h2>
      <span class="vg-pill" :class="chain.tone === 'healthy' ? 'vg-pill--healthy' : 'vg-pill--pending'">{{ chain.label }}</span>
    </div>
    <p>Live, read-only checks every 15 seconds while this tab is visible. Observations expire after 30 seconds.</p>
    <div class="sg-chain" role="list" aria-label="Live seal chain nodes">
      <div v-for="node in nodes" :key="node.name" class="sg-chain-node" :data-role="node.role" :data-status="node.tone" role="listitem" :aria-label="node.name">
        <strong>{{ node.name }}</strong>
        <span class="vg-pill" :class="node.tone === 'healthy' ? 'vg-pill--healthy' : node.tone === 'critical' ? 'vg-pill--rejected' : 'vg-pill--pending'">{{ node.label }}</span>
        <span class="detail">{{ node.resource ?? 'awaiting observation' }}</span>
        <time v-if="node.at" :datetime="node.at">Observed {{ new Date(node.at).toLocaleTimeString() }}</time>
      </div>
    </div>
    <p class="live-unsealed">{{ unsealed }}/3 members currently verified unsealed. Agent readiness is observed; these checks do not perform a Transit decrypt or prove recovery.</p>
    <button class="secondary-button" type="button" :disabled="status === 'pending'" @click="refresh()">{{ status === 'pending' ? 'Checking seal chain…' : 'Check seal chain' }}</button>
  </section>
</template>

<style scoped>
.live-seal-chain { padding: 20px; margin-bottom: 18px; }
.vg-section-header { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; justify-content: space-between; }
p { color: var(--vg-text-secondary); font-size: 13px; }
.sg-chain { display: flex; flex-wrap: wrap; gap: 12px; margin: 16px 0; }
.sg-chain-node { display: flex; flex: 1 1 160px; min-width: 0; flex-direction: column; gap: 8px; padding: 14px; border: 1px solid var(--vg-border); border-radius: 10px; }
.sg-chain-node strong { font-size: 14px; }
.vg-pill { align-self: flex-start; }
.detail, time { font-size: 11px; color: var(--vg-text-secondary); overflow-wrap: anywhere; }
</style>
