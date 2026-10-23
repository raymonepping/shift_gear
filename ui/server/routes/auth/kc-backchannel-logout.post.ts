import { backchannel } from '../../utils/backchannel'

export default defineEventHandler(async (event) => {
  if (Number(getHeader(event, 'content-length') ?? 0) > 16384) throw createError({ statusCode: 413 })
  const body = await readBody(event)
  if (typeof body?.logout_token !== 'string' || body.logout_token.length > 16384) throw createError({ statusCode: 400 })
  try { await backchannel(body.logout_token) } catch {
    throw createError({ statusCode: 400, statusMessage: 'logout token rejected' })
  }
  return null
})
