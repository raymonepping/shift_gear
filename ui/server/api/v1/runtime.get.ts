import { requireSession } from '../../utils/session'
import { readRuntime } from '../../utils/runtime'

export default defineEventHandler(async (event) => {
  await requireSession(event)
  return readRuntime()
})
