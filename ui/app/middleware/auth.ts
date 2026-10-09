// middleware/auth.ts — redirect to /signin when not authenticated.
export default defineNuxtRouteMiddleware(async (to) => {
  if (to.path === '/signin' || to.path.startsWith('/auth/') || to.path === '/_design') return
  try {
    await $fetch('/api/session')
  } catch (e) {
    const err = e as { statusCode?: number }
    if (err.statusCode === 401) return navigateTo('/signin')
  }
})
