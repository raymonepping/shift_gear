<script setup lang="ts">
const route = useRoute()
const { session, load } = useAuth()
const { sealChainLabel, startLive, stopLive } = useFleet()

onMounted(async () => {
  await load()
  startLive()
})
onBeforeUnmount(() => stopLive())

const nav = computed(() => [
  { to: '/', label: 'Fleet', icon: 'fleet', active: route.path === '/' },
  { to: '/layers', label: 'Layers', icon: 'layers', active: route.path === '/layers' },
  { to: '/engines', label: 'Engines', icon: 'engines', active: route.path === '/engines' },
  { to: '/pods', label: 'Pods', icon: 'pods', active: route.path === '/pods' },
  { to: '/routes', label: 'Routes', icon: 'routes', active: route.path === '/routes' },
  { to: '/operator', label: 'Operator', icon: 'operator', active: route.path === '/operator' },
  { to: '/ansible', label: 'Ansible', icon: 'ansible', active: route.path === '/ansible' },
  { to: '/agent', label: 'Agent', icon: 'agent', active: route.path === '/agent' },
  { to: '/audit', label: 'Audit', icon: 'audit', active: route.path === '/audit' },
  { to: '/cluster', label: 'Cluster', icon: 'cluster', active: route.path === '/cluster' },
])

const title = computed(() => {
  const labels: Record<string, string> = {
    '/': 'Fleet', '/layers': 'Layers', '/engines': 'Engines', '/pods': 'Pods',
    '/routes': 'Routes', '/operator': 'Operator', '/ansible': 'Ansible',
    '/agent': 'Agent', '/audit': 'Audit', '/cluster': 'Cluster',
  }
  return labels[route.path] ?? 'Shift Gear'
})

const chain = computed(() => sealChainLabel.value)
</script>

<template>
  <div class="sg-shell">
    <aside class="sg-sidebar" aria-label="Primary">
      <div class="sidebar-inner">
        <NuxtLink to="/" class="sidebar-brand" aria-label="Shift Gear home">
          <!-- Gear icon -->
          <svg class="brand-icon" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.6">
            <circle cx="12" cy="12" r="3"/>
            <path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/>
          </svg>
          <span class="brand-name">shift_gear</span>
        </NuxtLink>
        <nav class="sidebar-nav" aria-label="Primary navigation">
          <NuxtLink
            v-for="item in nav"
            :key="item.to"
            :to="item.to"
            class="nav-item"
            :class="{ active: item.active }"
            :aria-current="item.active ? 'page' : undefined"
          >
            <span class="nav-icon" aria-hidden="true">
              <svg v-if="item.icon === 'fleet'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h4l3-8 4 16 3-8h4" /></svg>
              <svg v-else-if="item.icon === 'layers'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="m12 3 9 5-9 5-9-5 9-5Z" /><path d="m3 13 9 5 9-5" /></svg>
              <svg v-else-if="item.icon === 'engines'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="7.5" cy="15.5" r="4.5" /><path d="m10.7 12.3 9.3-9.3M17 6l3 3M14.5 8.5l2 2" /></svg>
              <svg v-else-if="item.icon === 'pods'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="7" rx="2" /><rect x="3" y="13" width="18" height="7" rx="2" /><path d="M7 7.5h.01M7 16.5h.01" /></svg>
              <svg v-else-if="item.icon === 'routes'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 21V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v16M2 21h20M14 12h.01" /></svg>
              <svg v-else-if="item.icon === 'operator'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="7" width="20" height="14" rx="2" /><path d="M16 3v4M8 3v4" /></svg>
              <svg v-else-if="item.icon === 'ansible'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="m9 11 3 3L22 4" /><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" /></svg>
              <svg v-else-if="item.icon === 'agent'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3" /><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" /></svg>
              <svg v-else-if="item.icon === 'audit'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><path d="M14 2v6h6M16 13H8M16 17H8M10 9H8" /></svg>
              <svg v-else viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" /></svg>
            </span>
            <span class="nav-label">{{ item.label }}</span>
          </NuxtLink>
        </nav>
        <div class="sidebar-footer">
          <p class="foot-title">Shift Gear</p>
          <p class="foot-meta">Vault Enterprise · OpenShift · Terraform + Ansible</p>
          <p class="foot-meta">Observe-only console — actions run from the host.</p>
        </div>
      </div>
    </aside>

    <div class="sg-main">
      <div class="topbar-wrap">
        <header class="sg-topbar">
          <div class="topbar-left">
            <NuxtLink to="/" class="mobile-brand" aria-label="Shift Gear home">shift_gear</NuxtLink>
            <p class="page-title">{{ title }}</p>
            <nav class="mobile-nav" aria-label="Sections">
              <NuxtLink v-for="item in nav" :key="item.to" :to="item.to" :class="{ active: item.active }" :aria-current="item.active ? 'page' : undefined">{{ item.label }}</NuxtLink>
            </nav>
          </div>
          <div class="topbar-right">
            <span class="cluster-pill" :class="chain.tone" role="status" :aria-label="`Seal chain status: ${chain.label}`">
              <span class="cluster-dot" :class="{ live: chain.tone === 'healthy' }" aria-hidden="true" />
              <span class="cluster-label">{{ chain.label }}</span>
            </span>
            <div v-if="session" class="persona">
              <span class="persona-dot" aria-hidden="true" />
              <span class="persona-name">{{ session.displayName }}</span>
              <span class="persona-role">{{
                session.roles.isAdmin      ? 'ADMIN'
                : session.roles.isOperator ? 'OPERATOR'
                : session.roles.isEngineer ? 'ENGINEER'
                : session.roles.isAuditor  ? 'AUDITOR'
                : 'MEMBER'
              }}</span>
              <form method="post" action="/auth/logout" class="persona-out-form">
                <button type="submit" class="persona-out">Sign out</button>
              </form>
            </div>
          </div>
        </header>
      </div>
      <main id="main" class="sg-content">
        <slot />
      </main>
      <ShiftGearFooter />
    </div>
  </div>
</template>

<style scoped>
.sg-shell { display: flex; min-height: 100vh; }

.sg-sidebar {
  width: var(--sidebar-w);
  background: var(--vg-bg-shell);
  backdrop-filter: blur(22px) saturate(150%);
  -webkit-backdrop-filter: blur(22px) saturate(150%);
  border-right: 1px solid var(--vg-glass-border);
  box-shadow: inset -1px 0 0 rgba(255,255,255,0.6), 8px 0 32px -24px rgba(15,26,42,0.35);
  flex-shrink: 0; align-self: stretch;
}
.sidebar-inner { position: sticky; top: 0; height: 100vh; display: flex; flex-direction: column; }
.sidebar-brand { display: flex; align-items: center; gap: 10px; padding: 0 16px; height: var(--topbar-h); border-bottom: 1px solid var(--vg-border-subtle); color: var(--vg-text-primary); }
.brand-icon { width: 22px; height: 22px; flex-shrink: 0; color: var(--vg-action-primary); }
.brand-name { font-size: 18px; font-weight: 800; letter-spacing: -0.03em; color: var(--vg-text-primary); }
.sidebar-nav { flex: 1; padding: 12px 0; display: flex; flex-direction: column; gap: 2px; overflow-y: auto; }
.nav-item { display: flex; align-items: center; gap: 10px; margin: 0 8px; padding: 0 10px; height: 34px; font-size: 13px; font-weight: 550; color: var(--vg-text-secondary); border-radius: 8px; transition: background 0.18s var(--vg-ease-out), color 0.18s; }
.nav-item:hover { background: rgba(255,255,255,0.55); color: var(--vg-text-primary); }
.nav-item.active { background: rgba(255,255,255,0.85); color: var(--vg-text-primary); font-weight: 650; box-shadow: inset 0 0 0 1px rgba(15,26,42,0.08), 0 4px 12px -8px rgba(15,26,42,0.35); }
.nav-item.active .nav-icon { color: var(--vg-action-primary); }
.nav-icon { width: 16px; height: 16px; display: flex; flex-shrink: 0; }
.nav-icon svg { width: 16px; height: 16px; }
.sidebar-footer { padding: 14px 16px; border-top: 1px solid var(--vg-border-subtle); }
.foot-title { margin: 0; font-size: 12px; font-weight: 650; color: var(--vg-text-secondary); }
.foot-meta { margin: 2px 0 0; font-size: 11px; color: var(--vg-text-muted); line-height: 1.45; }

.sg-main { flex: 1; display: flex; flex-direction: column; min-width: 0; }
.topbar-wrap { position: sticky; top: 0; z-index: 10; padding: 12px 24px 0; }
.sg-topbar {
  height: var(--topbar-h);
  background: var(--vg-bg-shell);
  backdrop-filter: blur(22px) saturate(150%);
  -webkit-backdrop-filter: blur(22px) saturate(150%);
  border: 1px solid var(--vg-glass-border); border-radius: 14px;
  box-shadow: var(--vg-shadow-md), inset 0 1px 0 var(--vg-glass-hi);
  display: flex; align-items: center; justify-content: space-between; gap: 14px; padding: 0 20px;
}
.topbar-left { display: flex; align-items: center; gap: 12px; min-width: 0; }
.page-title { font-size: 15px; font-weight: 700; letter-spacing: -0.01em; color: var(--vg-text-primary); margin: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.mobile-brand { display: none; font-weight: 800; letter-spacing: -0.02em; color: var(--vg-text-primary); }
.mobile-nav { display: none; gap: 4px; }
.mobile-nav a { padding: 4px 9px; border-radius: 8px; font-size: 12px; font-weight: 600; color: var(--vg-text-secondary); }
.mobile-nav a.active { background: rgba(255,255,255,0.85); color: var(--vg-text-primary); box-shadow: inset 0 0 0 1px rgba(15,26,42,0.08); }
.topbar-right { display: flex; align-items: center; gap: 8px; flex-shrink: 0; }
.cluster-pill { display: flex; align-items: center; gap: 6px; padding: 4px 12px; border-radius: 100px; font-size: 12px; font-weight: 600; line-height: 1.2; white-space: nowrap; border: 1px solid transparent; }
.cluster-pill.healthy { background: var(--vg-healthy-bg); color: var(--vg-healthy); border-color: color-mix(in srgb, var(--vg-hue-green) 22%, transparent); }
.cluster-pill.degraded { background: var(--vg-pending-bg); color: var(--vg-pending); border-color: color-mix(in srgb, var(--vg-hue-amber) 28%, transparent); }
.cluster-pill.critical { background: var(--vg-critical-bg); color: var(--vg-critical); border-color: color-mix(in srgb, var(--vg-hue-red) 22%, transparent); }
.cluster-pill.unknown { background: color-mix(in srgb, var(--vg-hue-slate) 10%, transparent); color: var(--vg-text-muted); border-color: color-mix(in srgb, var(--vg-hue-slate) 20%, transparent); }
.cluster-dot { width: 6px; height: 6px; border-radius: 50%; background: currentColor; flex-shrink: 0; }
.cluster-dot.live { animation: vgPulse 2.4s ease infinite; box-shadow: 0 0 8px currentColor; }
.persona { display: flex; align-items: center; gap: 7px; padding: 3px 4px 3px 10px; border: 1px solid var(--vg-glass-border); border-radius: 100px; font-size: 12px; color: var(--vg-text-secondary); }
.persona-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--vg-action-bright); box-shadow: 0 0 0 2px color-mix(in srgb, var(--vg-hue-blue) 18%, transparent); }
.persona-name { font-weight: 650; color: var(--vg-text-primary); }
.persona-role { font-size: 10.5px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--vg-action-bright); }
.persona-out-form { display: contents; }
.persona-out { padding: 2px 9px; border-radius: 100px; font-weight: 600; color: var(--vg-text-secondary); background: var(--vg-hover); border: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; }
.persona-out:hover { color: var(--vg-text-primary); }
.persona-out:focus-visible { outline: 2px solid var(--vg-action-primary); outline-offset: 2px; }
.sg-content { flex: 1; padding: 20px 24px 40px; min-width: 0; }

@media (max-width: 900px) {
  .sg-sidebar { display: none; }
  .sg-topbar { height: auto; flex-wrap: wrap; padding-top: 8px; padding-bottom: 8px; row-gap: 6px; }
  .topbar-left { display: contents; }
  .mobile-nav { display: flex; order: 3; flex-basis: 100%; }
  .mobile-brand { display: inline; }
  .page-title { display: none; }
}
@media (max-width: 640px) {
  .persona-name, .persona-dot { display: none; }
  .topbar-wrap { padding: 10px 16px 0; }
  .sg-topbar { padding: 0 14px; }
  .sg-content { padding: 16px 16px 32px; }
}
</style>
