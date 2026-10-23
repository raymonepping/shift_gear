<script setup lang="ts">
withDefaults(defineProps<{ status: string; hasData: boolean; label?: string; code?: number }>(), { label: 'Observations', code: undefined })
defineEmits<{ retry: [] }>()
</script>

<template>
  <p v-if="status === 'pending' && !hasData" class="inline-notice" role="status">Loading {{ label.toLowerCase() }}…</p>
  <div v-else-if="status === 'error'" class="inline-notice" role="alert">
    {{ label }} could not be refreshed<span v-if="code && code >= 400 && code <= 599"> (HTTP {{ code }})</span>.
    {{ hasData ? 'Previous observations remain visible; their current state is not verified.' : 'No observation is available for this page.' }}
    <button type="button" class="secondary-button" @click="$emit('retry')">Retry observations</button>
  </div>
  <p v-else-if="status === 'success' && !hasData" class="inline-notice" role="status">No {{ label.toLowerCase() }} were returned.</p>
</template>
