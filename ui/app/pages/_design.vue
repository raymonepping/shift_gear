<script setup lang="ts">
// _design.vue — component sheet. Visible only when NUXT_PUBLIC_DESIGN_SHEET=true.
// Accessible at /design — not linked from the shell nav.
useHead({ title: 'Design system · Shift Gear' })
definePageMeta({ middleware: [] })

const enabled = useRuntimeConfig().public.designSheet === 'true'

const tones = ['default', 'good', 'warn', 'bad', 'gold'] as const
const pillVariants = ['healthy', 'approved', 'warn', 'rejected', 'muted'] as const
</script>

<template>
  <div v-if="enabled" class="sg-ds">
    <h1 class="sg-ds__title">Shift Gear — design system</h1>

    <section class="sg-ds__section">
      <h2>Colour tokens</h2>
      <div class="sg-ds__swatches">
        <div class="sg-swatch" style="background: var(--vg-ink)"><span>--vg-ink</span></div>
        <div class="sg-swatch" style="background: var(--vg-surface)"><span>--vg-surface</span></div>
        <div class="sg-swatch" style="background: var(--vg-well)"><span>--vg-well</span></div>
        <div class="sg-swatch" style="background: var(--vg-border)"><span>--vg-border</span></div>
        <div class="sg-swatch" style="background: var(--vg-hue-blue)"><span>--vg-hue-blue</span></div>
        <div class="sg-swatch" style="background: var(--vg-hue-green)"><span>--vg-hue-green</span></div>
        <div class="sg-swatch" style="background: var(--vg-hue-amber)"><span>--vg-hue-amber</span></div>
        <div class="sg-swatch" style="background: var(--vg-critical)"><span>--vg-critical</span></div>
        <div class="sg-swatch" style="background: var(--sg-layer-tf)"><span>--sg-layer-tf</span></div>
        <div class="sg-swatch" style="background: var(--sg-layer-ansible)"><span>--sg-layer-ansible</span></div>
        <div class="sg-swatch" style="background: var(--sg-layer-operator)"><span>--sg-layer-operator</span></div>
        <div class="sg-swatch" style="background: var(--sg-layer-agent)"><span>--sg-layer-agent</span></div>
        <div class="sg-swatch" style="background: var(--sg-gear-ink)"><span>--sg-gear-ink</span></div>
      </div>
    </section>

    <section class="sg-ds__section">
      <h2>Tiles</h2>
      <div class="vg-grid-4">
        <div v-for="t in tones" :key="t" class="vg-tile" :class="t !== 'default' ? `vg-tile--${t}` : ''">
          <span class="vg-tile__label">{{ t }}</span>
          <span class="vg-tile__value">42</span>
          <span class="vg-tile__sub">sub-label</span>
        </div>
      </div>
    </section>

    <section class="sg-ds__section">
      <h2>Pills</h2>
      <div class="sg-ds__row">
        <span v-for="v in pillVariants" :key="v" class="vg-pill" :class="`vg-pill--${v}`">{{ v }}</span>
      </div>
    </section>

    <section class="sg-ds__section">
      <h2>Inline notices</h2>
      <div class="sg-ds__col">
        <p class="inline-notice">Default notice — informational</p>
        <p class="inline-notice inline-notice--warn">Warning notice — action recommended</p>
        <p class="inline-notice inline-notice--error">Error notice — something failed</p>
      </div>
    </section>

    <section class="sg-ds__section">
      <h2>Glass card</h2>
      <div class="vg-glass sg-ds__glass">
        <div class="vg-section-header">
          <h3 class="vg-section-title">Section title</h3>
          <span class="sg-ds__muted">meta text</span>
        </div>
        <p>Content inside a glass card. Body font: {{ '14px / 1.65, Hanken Grotesk' }}</p>
        <code class="vg-table__mono">monospace: JetBrains Mono</code>
      </div>
    </section>

    <section class="sg-ds__section">
      <h2>Table</h2>
      <div class="vg-table-wrap">
        <table class="vg-table">
          <thead><tr><th>Column A</th><th>Column B</th><th>Status</th></tr></thead>
          <tbody>
            <tr><td>row-one</td><td class="vg-table__mono">0xdeadbeef</td><td><span class="vg-pill vg-pill--healthy">pass</span></td></tr>
            <tr><td>row-two</td><td class="vg-table__mono">0x00000000</td><td><span class="vg-pill vg-pill--rejected">fail</span></td></tr>
          </tbody>
        </table>
      </div>
    </section>

    <section class="sg-ds__section">
      <h2>Layer provenance badges</h2>
      <div class="sg-ds__row">
        <span class="sg-ds__badge sg-ds__badge--tf">Terraform</span>
        <span class="sg-ds__badge sg-ds__badge--ansible">Ansible</span>
        <span class="sg-ds__badge sg-ds__badge--operator">Operator</span>
        <span class="sg-ds__badge sg-ds__badge--agent">Agent</span>
      </div>
    </section>
  </div>

  <div v-else class="sg-ds__disabled">
    <p>Design sheet is disabled. Set <code>NUXT_PUBLIC_DESIGN_SHEET=true</code> to enable.</p>
  </div>
</template>

<style scoped>
.sg-ds { max-width: 1100px; margin: 0 auto; display: grid; gap: 32px; padding-bottom: 60px; }
.sg-ds__title { font-size: 28px; font-weight: 800; letter-spacing: -0.03em; margin: 0; }
.sg-ds__section { display: grid; gap: 14px; }
.sg-ds__section h2 { font-size: 16px; font-weight: 700; margin: 0; color: var(--vg-text-secondary); text-transform: uppercase; letter-spacing: 0.05em; font-size: 11px; }
.sg-ds__swatches { display: flex; gap: 10px; flex-wrap: wrap; }
.sg-swatch { width: 96px; height: 56px; border-radius: 10px; display: grid; place-items: end start; padding: 6px 8px; font-size: 10px; font-family: var(--vg-font-mono); color: #fff; text-shadow: 0 0 4px #000a; }
.sg-ds__row { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; }
.sg-ds__col { display: grid; gap: 8px; }
.sg-ds__glass { padding: 16px 20px; display: grid; gap: 10px; }
.sg-ds__muted { font-size: 12px; color: var(--vg-text-muted); }
.sg-ds__badge { font-size: 11px; font-weight: 700; padding: 3px 9px; border-radius: 100px; letter-spacing: 0.04em; }
.sg-ds__badge--tf { background: color-mix(in srgb, var(--sg-layer-tf) 15%, transparent); color: var(--sg-layer-tf); }
.sg-ds__badge--ansible { background: color-mix(in srgb, var(--sg-layer-ansible) 15%, transparent); color: var(--sg-layer-ansible); }
.sg-ds__badge--operator { background: color-mix(in srgb, var(--sg-layer-operator) 15%, transparent); color: var(--sg-layer-operator); }
.sg-ds__badge--agent { background: color-mix(in srgb, var(--sg-layer-agent) 15%, transparent); color: var(--sg-layer-agent); }
.sg-ds__disabled { text-align: center; padding: 60px; color: var(--vg-text-muted); font-size: 14px; }
</style>
