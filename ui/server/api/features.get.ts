// GET /api/features — optional add-ons the console can show (session required).
// rotation: installed | degraded | not-installed (the KV rotation add-on, ADR D17).
import { requireSession } from '../utils/session'
import { rotationFeature } from '../utils/rotation'

export default defineEventHandler(async (event) => {
  await requireSession(event)
  const rotation = await rotationFeature()
  return { rotation: rotation.feature }
})
