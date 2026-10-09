// nuxt.config.ts — Shift Gear UI.
//
// SPA (ssr: false) served by Nitro (BFF). Sign-in = Vault OIDC via Keycloak.
// The person's Vault token stays in a server-side session; nothing secret
// reaches the browser. Substrate domain is read at runtime from env vars;
// never hardcoded (lesson 19: never apps-crc.testing in the source).
import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '2026-10-01',
  ssr: false,
  devtools: { enabled: false },
  modules: ['@nuxt/eslint'],
  css: ['~/assets/css/main.css'],
  vite: { plugins: [tailwindcss()] },
  // typeCheck is run separately via `make ui-check` (nuxt typecheck).
  // Disabling it here avoids vue-tsc running inside the Docker build where
  // .nuxt/ stubs are freshly generated and some server-side globals may not
  // be fully resolved at that point.
  typescript: { strict: true, typeCheck: false },
  app: {
    head: {
      title: 'Shift Gear',
      htmlAttrs: { lang: 'en' },
      meta: [
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        { name: 'color-scheme', content: 'light' },
        { name: 'description', content: 'Shift Gear — Vault Enterprise on OpenShift. Terraform builds it. Ansible decorates it. VSO delivers.' },
        { name: 'theme-color', content: '#e9eef3' },
      ],
      link: [{ rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
    },
  },
  runtimeConfig: {
    // Server-only. Override with NUXT_<NAME> env vars in the Deployment.
    vaultAddr: 'https://vault-active.sg-vault.svc:8200',   // NUXT_VAULT_ADDR
    vaultNamespace: 'shift-gear',                           // NUXT_VAULT_NAMESPACE
    vaultCaFile: '/ca/ca.crt',                              // NUXT_VAULT_CA_FILE
    oidcRedirectUri: '',                                    // NUXT_OIDC_REDIRECT_URI — set by ansible ux
    keycloakLogoutUrl: '',                                  // NUXT_KEYCLOAK_LOGOUT_URL — set by terraform workloads
    evidenceDir: '/evidence',                               // NUXT_EVIDENCE_DIR — ConfigMap sg-evidence
    auditApiBase: '',                                       // NUXT_AUDIT_API_BASE — internal API server
    kubeHost: '',                                           // NUXT_KUBE_HOST — e.g. https://api.crc.testing:6443
    kubeToken: '',                                          // NUXT_KUBE_TOKEN — service account token
    public: {
      refreshSeconds: 15,
      designSheet: 'false',  // NUXT_PUBLIC_DESIGN_SHEET=true enables /_design
    },
  },
  nitro: {
    storage: { sessions: { driver: 'memory' } },
    routeRules: {
      '/api/**': { headers: { 'cache-control': 'no-store' } },
    },
  },
  routeRules: {
    '/**': {
      headers: {
        'Content-Security-Policy':
          "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; "
          + "script-src 'self' 'unsafe-inline'; font-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; object-src 'none'",
        'X-Frame-Options': 'DENY',
        'X-Content-Type-Options': 'nosniff',
        'Referrer-Policy': 'no-referrer',
        'Cache-Control': 'no-store',
      },
    },
    '/_nuxt/**': { headers: { 'Cache-Control': 'public, max-age=31536000, immutable' } },
  },
})
