<script setup lang="ts">
import { OWNERS, IDENTITIES, type ExplorerDeclaration } from '../../shared/explorer'
import type { Observation } from '../../shared/observation'

useHead({ title: 'Policy and ownership · Shift Gear' })
definePageMeta({ middleware: ['auth'] })
const { data, status, error, refresh } = await useFetch<{
  state: 'published' | 'unavailable'; evidence: Observation; declaration: ExplorerDeclaration | null
}>('/api/v1/explorer', { server: false, lazy: true })
const owner = ref('')
const identity = ref('')
const expectation = ref('')
const query = ref('')
const declaration = computed(() => data.value?.declaration)
const owners = computed(() => (declaration.value?.ownership ?? []).filter(row => !owner.value || row.owner === owner.value))
const boundaries = computed(() => (declaration.value?.boundary ?? []).filter(row =>
  (!identity.value || row.token === identity.value) && (!expectation.value || row.expect.startsWith(`${expectation.value}:`))
  && (!query.value || row.path.toLowerCase().includes(query.value.toLowerCase()))))
</script>

<template>
  <div class="explorer">
    <section class="vg-hero fleet-hero" aria-labelledby="explorer-title">
      <p class="eyebrow">Declared boundaries · read only</p>
      <h1 id="explorer-title">Policy and ownership</h1>
      <p>Find who owns a field, which runtime writer may change it, and which check covers that boundary.</p>
      <p>These are published declarations, not a live capability check or a grant to your session. Access is enforced by Vault and Kubernetes.</p>
      <button class="secondary-button" type="button" :disabled="status === 'pending'" @click="refresh()">Reload published declarations</button>
    </section>
    <SourceState :status="status" :has-data="!!data" :code="error?.statusCode" label="Explorer declarations" @retry="refresh()" />
    <section v-if="data && !declaration" class="panel vg-glass" role="status">
      <h2>Declarations unavailable</h2>
      <p>The published snapshot has no valid ownership and boundary registry. An older deployment may not publish it yet. No permissions are inferred from your UI role.</p>
      <NuxtLink to="/help#evidence">Investigate evidence publication</NuxtLink>
    </section>
    <template v-if="declaration">
      <section class="panel vg-glass provenance" aria-labelledby="provenance-title">
        <h2 id="provenance-title">Declaration provenance</h2>
        <p>Published snapshot · at last reload: {{ data?.evidence.freshness }} · {{ data?.evidence.availability }}. Reload reads the mounted publication; it does not run checks.</p>
        <dl>
          <div><dt>Published at</dt><dd>{{ data?.evidence.observedAt ?? 'Not reported' }}</dd></div>
          <div><dt>Cluster</dt><dd>{{ data?.evidence.clusterId ?? 'Not reported' }}</dd></div>
          <div><dt>Run</dt><dd>{{ data?.evidence.runId ?? 'Not reported' }}</dd></div>
          <div><dt>Observation</dt><dd>{{ data?.evidence.observationId ?? 'Not reported' }}</dd></div>
          <div><dt>Publication input digest</dt><dd>{{ declaration.inputDigest }}</dd></div>
          <div v-for="source in declaration.sources" :key="source.path"><dt>{{ source.path }} · SHA-256</dt><dd>{{ source.sha256 }}</dd></div>
        </dl>
        <p>Hashes identify the declared source bytes at publication. They do not establish review approval, a passing proof, or the current state of the cluster.</p>
        <NuxtLink to="/help#ownership">Ownership and capability runbook</NuxtLink>
      </section>
      <section class="panel vg-glass" aria-labelledby="owners-title">
        <h2 id="owners-title">Field ownership</h2>
        <label for="explorer-owner">Owner</label>
        <select id="explorer-owner" v-model="owner"><option value="">All owners</option><option v-for="item in OWNERS" :key="item">{{ item }}</option></select>
        <p role="status">{{ owners.length }} of {{ declaration.ownership.length }} ownership declarations</p>
        <div class="ownership-grid">
          <article v-for="row in owners" :key="row.id" class="ownership-card vg-card">
            <p class="eyebrow">{{ row.owner }}</p><h3>{{ row.area }}</h3>
            <dl>
              <div><dt>Desired scope</dt><dd>{{ row.scope }}</dd></div>
              <div><dt>Runtime writer</dt><dd>{{ row.runtimeWriter }}</dd></div>
              <div><dt>Allowed exception / limit</dt><dd>{{ row.exception }}</dd></div>
              <div><dt>Verification method</dt><dd>{{ row.check }}</dd></div>
            </dl>
            <NuxtLink :to="`/help#${row.runbook}`">Investigation steps for {{ row.area }}</NuxtLink>
          </article>
        </div>
      </section>
      <section class="panel vg-glass" aria-labelledby="boundary-title">
        <h2 id="boundary-title">Expected capability matrix</h2>
        <p>Maintenance identity labels name the four scoped automation identities, not token values. These selected operations describe expected allow/deny behavior; they are not a complete ACL or a live result.</p>
        <p>The host's boundary proof asks Vault for actual capabilities. This page does not run that proof or show the signed-in user's permissions.</p>
        <div class="explorer-filters">
          <div><label for="explorer-identity">Maintenance identity</label><select id="explorer-identity" v-model="identity"><option value="">All identities</option><option v-for="item in IDENTITIES" :key="item">{{ item }}</option></select></div>
          <div><label for="explorer-expectation">Expectation</label><select id="explorer-expectation" v-model="expectation"><option value="">All expectations</option><option value="allow">Allow</option><option value="deny">Deny</option></select></div>
          <div><label for="explorer-path">Declared path contains</label><input id="explorer-path" v-model="query" type="search" maxlength="120" /></div>
        </div>
        <p role="status">{{ boundaries.length }} of {{ declaration.boundary.length }} expected operations</p>
        <div class="vg-table-wrap" tabindex="0" role="region" aria-label="Expected capability operations">
          <table class="vg-table"><caption class="sr-only">Published expected operations, not live capability results</caption><thead><tr><th scope="col">Identity</th><th scope="col">Vault</th><th scope="col">Declared path</th><th scope="col">Expected</th></tr></thead>
            <tbody><tr v-for="row in boundaries" :key="`${row.token}:${row.vault}:${row.path}`"><td>{{ row.token }}</td><td>{{ row.vault }}</td><td class="declared-path">{{ row.path }}</td><td>{{ row.expect }}</td></tr>
              <tr v-if="!boundaries.length"><td colspan="4">No declared operations match these filters.</td></tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>

<style scoped>
.explorer { display: grid; grid-template-columns: minmax(0, 1fr); gap: 20px; }
.explorer .panel { min-width: 0; }
.explorer a { text-decoration: underline; text-underline-offset: 0.15em; }
.explorer dl { margin: 0; display: grid; gap: 12px; }
.explorer dt { font-weight: 650; font-size: 12px; color: var(--vg-text-secondary); }
.explorer dd { margin: 4px 0 0; overflow-wrap: anywhere; }
.provenance dd { font-family: var(--font-mono); font-size: 12px; }
.ownership-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(300px, 100%), 1fr)); gap: 16px; margin-top: 16px; }
.ownership-card { min-width: 0; padding: 18px; overflow-wrap: anywhere; }
.ownership-card h3 { margin: 8px 0 16px; }
.ownership-card a { display: inline-block; margin-top: 16px; }
.explorer-filters { display: flex; flex-wrap: wrap; align-items: end; gap: 16px; }
.explorer-filters > div { min-width: 0; }
.explorer label { display: block; margin-bottom: 6px; font-size: 13px; font-weight: 600; }
.explorer select, .explorer input { box-sizing: border-box; min-width: 0; max-width: 100%; padding: 8px; color: var(--vg-text-primary); background: var(--vg-bg-card); border: 1px solid var(--vg-border); border-radius: 6px; font: inherit; }
.declared-path { overflow-wrap: anywhere; }
</style>
