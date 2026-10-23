<script setup lang="ts">
const { data, status, refresh, now, failed } = useRuntime()
const unavailable = computed(() => data.value?.sources.filter(source => source.state !== 'available').length ?? 0)
const age = (at: string | null) => at ? Math.max(0, Math.floor((now.value - Date.parse(at)) / 1000)) : null
</script>

<template>
  <details class="runtime-sources" aria-live="off">
    <summary>Runtime sources · {{ status === 'error' ? 'unavailable' : status === 'pending' && !data ? 'checking' : unavailable ? `${unavailable} unavailable or invalid` : 'read-only checks' }}</summary>
    <p>These checks are independent of the published snapshot. Ready replicas and VSO status do not prove delivery of a particular rotation.</p>
    <p v-if="status === 'error'" role="alert">Runtime observer unavailable. Current runtime health is not verified.</p>
    <ul v-if="data">
      <li v-for="source in data.sources" :key="source.name">
        <strong>{{ source.name }}</strong>: {{ failed ? 'previous observation only' : source.state }}
        <span v-if="source.reason"> · {{ source.reason }}</span>
        <span v-if="source.observedAt"> · {{ age(source.observedAt) }} seconds old{{ (age(source.observedAt) ?? 0) > 30 ? ' · stale' : '' }}</span>
        <span> · Owner: {{ source.owner }} · {{ source.resource }}</span>
        <dl v-if="source.state === 'available'">
          <div v-for="(value, key) in source.data" :key="key"><dt>{{ key }}</dt><dd>{{ value ?? 'not reported' }}</dd></div>
        </dl>
        <NuxtLink :to="`/help#${/^(Vault|Seal)/.test(source.name) ? 'vault' : source.name.startsWith('Identity') ? 'identity' : 'delivery'}`">Investigation steps</NuxtLink>
      </li>
    </ul>
    <button type="button" :disabled="status === 'pending'" @click="refresh()">Check runtime sources</button>
  </details>
</template>

<style scoped>
.runtime-sources { width: 100%; overflow-wrap: anywhere; }
summary { cursor: pointer; font-weight: 600; }
li { margin: 12px 0; }
dl { display: flex; flex-wrap: wrap; gap: 12px; margin: 6px 0; }
dt { color: var(--vg-text-secondary); }
dd { margin: 0; }
</style>
