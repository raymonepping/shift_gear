import type { RotationFeature } from '../../shared/kv-rotation'

/** Optional add-ons the BFF detected (ADR D17). Unknown until loaded; never guessed. */
export function useFeatures() {
  const features = useState<{ rotation: RotationFeature } | null>('features', () => null)

  async function load(force = false) {
    if (features.value && !force) return features.value
    try {
      features.value = await $fetch<{ rotation: RotationFeature }>('/api/features')
    } catch {
      features.value = null
    }
    return features.value
  }

  const rotationVisible = computed(() => features.value?.rotation === 'installed' || features.value?.rotation === 'degraded')
  return { features, load, rotationVisible }
}
