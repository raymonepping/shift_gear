<script setup lang="ts">
const route = useRoute()
const isSignIn = computed(() => route.path === '/signin')
</script>

<template>
  <NuxtLoadingIndicator color="#0369a1" :height="2" />
  <a href="#main" class="skip-link">Skip to content</a>
  <NuxtPage v-if="isSignIn" />
  <AppShell v-else>
    <NuxtPage />
  </AppShell>
</template>
