<script setup lang="ts">
// Sign-in: Vault is the OIDC client of Keycloak (LDAP). One button. One truth.
definePageMeta({ layout: 'bare', middleware: [] })
useHead({ title: 'Sign in · Shift Gear' })

const route = useRoute()
const error = computed(() => (route.query.error as string) || '')

// In dev with NUXT_DEV_PERSONAS=true, hint which users are available
const devHint = computed(() =>
  import.meta.dev ? 'Dev mode: ada / ben / cleo / dirk / finn — all via Keycloak LDAP' : '',
)
</script>

<template>
  <div class="sg-signin">
    <section class="vg-hero sg-signin__hero">
      <div class="sg-signin__gear" aria-hidden="true">
        <svg viewBox="0 0 64 64" fill="none" stroke="currentColor" stroke-width="2">
          <circle cx="32" cy="32" r="10"/>
          <path d="M32 4v6M32 54v6M4 32h6M54 32h6M11.5 11.5l4.2 4.2M48.3 48.3l4.2 4.2M11.5 52.5l4.2-4.2M48.3 15.7l4.2-4.2"/>
          <path d="M28 4.5a28 28 0 0 0-5.2 1.8L20 2.8A32 32 0 0 0 2.8 20l3.5 2.8A28 28 0 0 0 4.5 28H1a31 31 0 0 0 0 8h3.5a28 28 0 0 0 1.8 5.2L2.8 44A32 32 0 0 0 20 61.2l2.8-3.5A28 28 0 0 0 28 59.5V63a31 31 0 0 0 8 0v-3.5a28 28 0 0 0 5.2-1.8L44 61.2A32 32 0 0 0 61.2 44l-3.5-2.8A28 28 0 0 0 59.5 36H63a31 31 0 0 0 0-8h-3.5a28 28 0 0 0-1.8-5.2L61.2 20A32 32 0 0 0 44 2.8l-2.8 3.5A28 28 0 0 0 36 4.5V1a31 31 0 0 0-8 0v3.5z" opacity=".35"/>
        </svg>
      </div>
      <h1 class="sg-signin__title">One vault.<br/>Every layer.</h1>
      <p class="sg-signin__strapline">
        Terraform deploys it. Ansible configures it. OpenShift runs it.
        The Vault Secrets Operator syncs it. Sign in to see how they fit together.
      </p>
      <a class="sg-signin__btn" href="/auth/login" data-testid="sign-in">
        <svg class="sg-signin__btn-icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
          <path d="M6 2H3a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3M11 11l3-3-3-3M14 8H6"/>
        </svg>
        Sign in with Vault OIDC
      </a>
      <p class="sg-signin__how">
        Signing in is a Vault login: Vault asks Keycloak who you are,
        and your LDAP groups become Vault policies.
      </p>
      <p v-if="devHint" class="sg-signin__dev" aria-live="polite">{{ devHint }}</p>
      <p v-if="error" class="inline-notice inline-notice--error" role="alert">{{ error }}</p>
    </section>
  </div>
</template>

<style scoped>
.sg-signin {
  min-height: calc(100vh - 80px);
  display: grid;
  place-items: center;
  background: var(--vg-bg);
}
.sg-signin__hero {
  width: min(620px, 100%);
  padding: 32px clamp(20px, 5vw, 44px);
  display: grid;
  gap: 14px;
  justify-items: start;
}
.sg-signin__gear {
  width: 72px;
  height: 72px;
  color: var(--vg-text-muted);
  margin-bottom: 4px;
}
.sg-signin__title {
  margin: 0;
  font-size: clamp(28px, 5vw, 40px);
  font-weight: 800;
  letter-spacing: -0.035em;
  line-height: 1.1;
}
.sg-signin__strapline {
  margin: 0;
  max-width: 52ch;
  color: var(--vg-text-secondary);
  line-height: 1.6;
}
.sg-signin__btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  margin-top: 8px;
  padding: 11px 22px;
  border-radius: 10px;
  background: var(--vg-ink);
  color: #fff;
  font-size: 15px;
  font-weight: 600;
  text-decoration: none;
  transition: opacity .15s;
}
.sg-signin__btn:hover { opacity: .85; }
.sg-signin__btn-icon {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
}
.sg-signin__how {
  font-size: 12.5px;
  color: var(--vg-text-muted);
  max-width: 50ch;
}
.sg-signin__dev {
  font-size: 12px;
  color: var(--sg-layer-ansible);
  font-family: var(--vg-font-mono);
  background: color-mix(in srgb, var(--sg-layer-ansible) 10%, transparent);
  padding: 6px 10px;
  border-radius: 6px;
}
</style>
