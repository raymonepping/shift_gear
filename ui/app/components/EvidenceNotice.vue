<script setup lang="ts">
const { fleet, failed } = useFleet()
const evidence = computed(() => fleet.value?.evidence)
const tick = ref(Date.now())
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => { tick.value = Date.now() }, 10000) })
onBeforeUnmount(() => clearInterval(timer))
const age = computed(() => evidence.value?.observedAt
  ? Math.max(0, Math.floor((tick.value - Date.parse(evidence.value.observedAt)) / 1000)) : null)
const current = computed(() => !failed.value && evidence.value?.availability === 'available'
  && age.value !== null && age.value <= 120)
</script>

<template>
  <aside class="evidence-notice" role="status" aria-label="Evidence source and freshness">
    <strong>{{ current ? 'Published snapshot' : 'Published snapshot is not current' }}</strong>
    <span v-if="age !== null">Observed {{ age }} seconds ago.</span>
    <span v-else>Observation missing or invalid.</span>
    <span>Refresh reloads published evidence. Seal-chain status uses independent live checks every 15 seconds.</span>
    <span v-if="fleet?.automationRun">Latest recorded attempt: provisioning {{ fleet.automationRun.provisioning }}, publication {{ fleet.automationRun.publication }}.</span>
    <details><summary>Evidence details</summary>
      <p>Host operator: run <code>make ux</code> to publish a new observation.</p>
      <p>Cluster: {{ evidence?.clusterId ?? 'not reported' }} · Run: {{ evidence?.runId ?? 'not reported' }}</p>
      <p>Observation: {{ evidence?.observationId ?? 'not reported' }} · Source: snapshot</p>
      <NuxtLink to="/help#evidence">Evidence investigation guide</NuxtLink>
    </details>
    <RuntimeStatus />
  </aside>
</template>

<style scoped>
.evidence-notice { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 16px; padding: 12px; border: 1px solid var(--vg-border); border-radius: 10px; font-size: 12px; }
.evidence-notice p { overflow-wrap: anywhere; }
</style>
