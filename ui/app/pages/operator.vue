<script setup lang="ts">
import type { OperatorResponse, VsoSecret } from '../../shared/types'

useHead({ title: 'Operator · Shift Gear' })
definePageMeta({ middleware: ['auth'] })

const { session } = useAuth()
const canRotate = computed(() => session.value?.roles.isOperator || session.value?.roles.isAdmin || false)

const { data, status, refresh } = await useFetch<OperatorResponse>('/api/v1/operator/secrets', { server: false, lazy: true })
const checking = computed(() => status.value === 'pending')
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => refresh(), 15_000) })
onBeforeUnmount(() => clearInterval(timer))

const rotating = ref<string | null>(null)
const rotateError = ref<string | null>(null)
const rotateSuccess = ref<string | null>(null)

async function rotate(name: string) {
  rotating.value = name
  rotateError.value = null
  rotateSuccess.value = null
  try {
    await $fetch(`/api/v1/operator/static-secrets/${encodeURIComponent(name)}/rotate`, { method: 'POST' })
    // Poll until lastSyncTime changes
    const before = data.value?.staticSecrets.find(s => s.name === name)?.lastSyncTime
    let attempts = 0
    while (attempts < 14) {
      await new Promise(r => setTimeout(r, 3_000))
      await refresh()
      const after = data.value?.staticSecrets.find(s => s.name === name)?.lastSyncTime
      if (after && after !== before) { rotateSuccess.value = name; break }
      attempts++
    }
    if (!rotateSuccess.value) rotateError.value = `Sync did not complete within 45 s for ${name}`
  } catch (e) {
    rotateError.value = `Rotation failed: ${(e as { message?: string }).message ?? 'unknown error'}`
  } finally {
    rotating.value = null
  }
}

const ago = (at: string | null | undefined): string => {
  if (!at) return 'never'
  const minutes = Math.max(0, Math.round((Date.now() - new Date(at).getTime()) / 60_000))
  if (minutes < 1) return 'just now'
  if (minutes < 90) return `${minutes} min ago`
  return `${Math.round(minutes / 60)} h ago`
}

function syncStatus(s: VsoSecret) {
  if (s.syncError) return { tone: 'state-fail', text: 'error' }
  if (!s.lastSyncTime) return { tone: 'state-unknown', text: 'never synced' }
  return { tone: 'state-pass', text: ago(s.lastSyncTime) }
}
</script>

<template>
  <div>
    <section class="vg-hero fleet-hero" aria-labelledby="operator-title">
      <div class="hero-head">
        <div>
          <p class="eyebrow">Vault Secrets Operator · Kubernetes native secret delivery</p>
          <h1 id="operator-title">Operator</h1>
          <p>Secrets synced by the Vault Secrets Operator. No Vault token in any workload pod. The pod sees a Kubernetes Secret — that is all.</p>
        </div>
        <button class="secondary-button" type="button" :disabled="checking" @click="refresh()">
          <svg class="button-icon" :class="{ spinning: checking }" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5" /></svg>
          {{ checking ? 'Checking…' : 'Refresh' }}
        </button>
      </div>
    </section>

    <p v-if="rotateError" class="inline-notice error" role="alert">{{ rotateError }}</p>
    <p v-if="rotateSuccess" class="inline-notice" role="status" style="background:var(--vg-healthy-bg);color:var(--vg-healthy);">{{ rotateSuccess }} rotated and synced successfully.</p>

    <div v-if="checking && !data" class="skeleton" aria-label="Loading"><div /><div /></div>

    <template v-if="data">
      <div class="op-grid">
        <!-- Left: CRD cards -->
        <section class="sg-layer-panel sg-layer-panel--operator" aria-labelledby="vss-title">
          <div class="panel-head">
            <div>
              <p class="sg-provenance-badge">Vault Operator</p>
              <h2 id="vss-title">VaultStaticSecrets</h2>
            </div>
          </div>
          <div class="vso-list">
            <article v-for="s in data.staticSecrets" :key="s.name" class="vso-card vg-card">
              <div class="vso-head">
                <span class="mono vso-name">{{ s.name }}</span>
                <span class="door-chip" :class="syncStatus(s).tone"><i aria-hidden="true" />{{ syncStatus(s).text }}</span>
              </div>
              <dl class="vso-meta">
                <div><dt>Vault path</dt><dd class="mono">{{ s.vaultPath }}</dd></div>
                <div><dt>→ Secret</dt><dd class="mono">{{ s.destinationSecret }}</dd></div>
                <div v-if="s.syncError"><dt>Error</dt><dd class="error-text">{{ s.syncError }}</dd></div>
              </dl>
              <div v-if="canRotate" class="vso-actions">
                <button
                  type="button"
                  class="secondary-button"
                  :disabled="rotating === s.name"
                  @click="rotate(s.name)"
                >
                  <svg v-if="rotating === s.name" class="button-icon spinning" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5" /></svg>
                  {{ rotating === s.name ? 'Syncing…' : 'Rotate' }}
                </button>
              </div>
            </article>
          </div>

          <div class="panel-head" style="margin-top:20px">
            <h2 id="vds-title">VaultDynamicSecrets</h2>
          </div>
          <div class="vso-list">
            <article v-for="s in data.dynamicSecrets" :key="s.name" class="vso-card vg-card">
              <div class="vso-head">
                <span class="mono vso-name">{{ s.name }}</span>
                <span class="door-chip" :class="syncStatus(s).tone"><i aria-hidden="true" />{{ syncStatus(s).text }}</span>
              </div>
              <dl class="vso-meta">
                <div><dt>Vault path</dt><dd class="mono">{{ s.vaultPath }}</dd></div>
                <div><dt>→ Secret</dt><dd class="mono">{{ s.destinationSecret }}</dd></div>
              </dl>
            </article>
          </div>
        </section>

        <!-- Right: workloads -->
        <section class="sg-layer-panel sg-layer-panel--tf" aria-labelledby="wl-title">
          <div class="panel-head">
            <div>
              <p class="sg-provenance-badge">Terraform · Ansible</p>
              <h2 id="wl-title">Workloads</h2>
            </div>
          </div>
          <div class="vso-list">
            <article v-for="wl in data.workloads" :key="wl.name" class="vso-card vg-card">
              <div class="vso-head">
                <span class="mono vso-name">{{ wl.name }}</span>
                <span class="door-chip" :class="wl.readyReplicas >= wl.replicas ? 'state-pass' : 'state-warn'">
                  <i aria-hidden="true" />{{ wl.readyReplicas }}/{{ wl.replicas }} ready
                </span>
              </div>
              <dl class="vso-meta">
                <div><dt>Namespace</dt><dd>{{ wl.namespace }}</dd></div>
                <div v-if="wl.lastSecretUpdate"><dt>Last secret</dt><dd>{{ ago(wl.lastSecretUpdate) }}</dd></div>
                <div v-if="wl.mountedSecretKeys.length"><dt>Mounted keys</dt><dd class="mono">{{ wl.mountedSecretKeys.join(', ') }}</dd></div>
              </dl>
            </article>
          </div>
        </section>
      </div>
    </template>
  </div>
</template>

<style scoped>
.op-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
@media (max-width: 900px) { .op-grid { grid-template-columns: 1fr; } }
.vso-list { display: grid; gap: 10px; }
.vso-card { padding: 14px 16px; display: flex; flex-direction: column; gap: 8px; }
.vso-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; flex-wrap: wrap; }
.vso-name { font-size: 13px; font-weight: 700; color: var(--vg-text-primary); }
.vso-meta { margin: 0; display: grid; gap: 4px; font-size: 12px; }
.vso-meta div { display: flex; gap: 6px; align-items: baseline; }
.vso-meta dt { color: var(--vg-text-muted); flex-shrink: 0; }
.vso-meta dd { margin: 0; color: var(--vg-text-primary); overflow-wrap: anywhere; }
.vso-actions { display: flex; justify-content: flex-end; margin-top: 4px; }
.error-text { color: var(--vg-critical); font-size: 11.5px; }
</style>
