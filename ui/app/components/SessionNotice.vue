<script setup lang="ts">
const { session, load } = useAuth()
const now = ref(Date.now())
const remaining = computed(() => session.value ? Math.ceil((Date.parse(session.value.expiresAt) - now.value) / 60000) : null)
watch(session, () => { now.value = Date.now() })
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => { now.value = Date.now() }, 10000) })
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <p v-if="remaining !== null && remaining <= 5" class="inline-notice" role="status">
    {{ remaining > 0 ? `Your session expires in about ${remaining} minutes.` : 'Your session has expired.' }} Save your investigation notes, then sign in again.
    <button v-if="remaining > 0" type="button" @click="load(true)">Check session</button>
    <NuxtLink v-else to="/signin?reason=expired">Sign in</NuxtLink>
  </p>
</template>
