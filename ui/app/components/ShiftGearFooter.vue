<script setup lang="ts">
const year = new Date().getFullYear()
const keyOpen = ref(false)
if (import.meta.client) {
  keyOpen.value = localStorage.getItem('sg-layer-key') !== 'false'
}
function toggleKey() {
  keyOpen.value = !keyOpen.value
  if (import.meta.client) localStorage.setItem('sg-layer-key', String(keyOpen.value))
}
const layerKey = [
  { label: 'Terraform', color: 'var(--vg-hue-indigo)', swatch: '#4f5bd5' },
  { label: 'Ansible', color: 'var(--vg-hue-green)', swatch: '#137333' },
  { label: 'Vault Operator', color: 'var(--vg-hue-amber)', swatch: '#c2620a' },
  { label: 'Vault Agent', color: 'var(--vg-hue-violet)', swatch: '#6d28d9' },
]
const footerLinks = [
  { label: 'Build', to: '/layers' },
  { label: 'Decorate', to: '/ansible' },
  { label: 'Seal', to: '/cluster' },
  { label: 'Prove', to: '/layers' },
]
</script>

<template>
  <footer class="rp-footer" aria-label="Site footer">
    <div class="rp-footer__rail" aria-hidden="true" />
    <div class="rp-footer__inner">
      <div class="rp-footer__key-row">
        <button
          type="button"
          class="rp-footer__key-toggle"
          :aria-expanded="keyOpen"
          aria-controls="footer-layer-key"
          @click="toggleKey"
        >
          <svg class="rp-footer__chevron" :class="{ 'rp-footer__chevron--open': keyOpen }" viewBox="0 0 10 10" fill="currentColor" aria-hidden="true"><path d="M3 2l4 3-4 3" /></svg>
          Layer key
        </button>
        <div v-if="keyOpen" id="footer-layer-key" class="rp-footer__key-items">
          <span v-for="k in layerKey" :key="k.label" class="rp-footer__key-item">
            <span class="rp-footer__swatch" :style="{ background: k.swatch }" aria-hidden="true" />
            {{ k.label }}
          </span>
        </div>
      </div>
      <div class="rp-footer__body">
        <p class="rp-footer__tagline">
          <NuxtLink v-for="(lnk, i) in footerLinks" :key="lnk.label" :to="lnk.to" class="footer-word">
            <template v-if="i > 0"><i aria-hidden="true">·</i></template>{{ lnk.label }}
          </NuxtLink>
        </p>
        <p class="rp-footer__tagline" aria-label="Footer tagline">
          <em>Terraform builds the house. Ansible decorates it. Vault keeps the keys.</em>
        </p>
        <div class="rp-footer__bottom">
          <p class="rp-footer__copy">
            © {{ year }}&nbsp;
            <span
              class="sig-name"
              data-name="Raymon Epping"
              tabindex="0"
              role="presentation"
            >Raymon Epping</span>
          </p>
          <div class="rp-footer__socials">
            <a href="https://github.com/raymonepping" target="_blank" rel="noopener noreferrer" class="rp-footer__social-link" aria-label="GitHub: raymonepping">
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2C6.48 2 2 6.48 2 12c0 4.42 2.87 8.17 6.84 9.49.5.09.68-.22.68-.48v-1.69c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.89 1.52 2.34 1.08 2.91.83.09-.65.35-1.08.63-1.33-2.22-.25-4.56-1.11-4.56-4.95 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.64 0 0 .84-.27 2.75 1.02A9.56 9.56 0 0 1 12 6.8c.85.004 1.71.115 2.51.34 1.91-1.29 2.75-1.02 2.75-1.02.55 1.37.2 2.39.1 2.64.64.7 1.03 1.59 1.03 2.68 0 3.85-2.34 4.7-4.57 4.94.36.31.68.92.68 1.85v2.74c0 .27.18.58.69.48A10.01 10.01 0 0 0 22 12c0-5.52-4.48-10-10-10z" /></svg>
            </a>
            <a href="https://x.com/doctor_nosql" target="_blank" rel="noopener noreferrer" class="rp-footer__social-link" aria-label="X: doctor_nosql">
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.401 6.231H2.744l7.736-8.847L2.044 2.25h6.672l4.254 5.622 5.274-5.622zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>
            </a>
            <a href="https://linkedin.com/in/raymonepping" target="_blank" rel="noopener noreferrer" class="rp-footer__social-link" aria-label="LinkedIn: raymonepping">
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 0 1-2.063-2.065 2.064 2.064 0 1 1 2.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z"/></svg>
            </a>
            <a href="https://medium.com/@raymonepping" target="_blank" rel="noopener noreferrer" class="rp-footer__social-link" aria-label="Medium: @raymonepping">
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M13.54 12a6.8 6.8 0 0 1-6.77 6.82A6.8 6.8 0 0 1 0 12a6.8 6.8 0 0 1 6.77-6.82A6.8 6.8 0 0 1 13.54 12zm7.42 0c0 3.54-1.51 6.42-3.38 6.42-1.87 0-3.39-2.88-3.39-6.42s1.52-6.42 3.39-6.42 3.38 2.88 3.38 6.42M24 12c0 3.17-.53 5.75-1.19 5.75-.66 0-1.19-2.58-1.19-5.75s.53-5.75 1.19-5.75S24 8.83 24 12z"/></svg>
            </a>
          </div>
        </div>
      </div>
    </div>
  </footer>
</template>
