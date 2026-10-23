import { requireSession } from '../../utils/session'
import { readEvidence } from '../../utils/evidence'
import { explorerDeclaration } from '../../../shared/explorer'

export default defineEventHandler(async (event) => {
  await requireSession(event)
  if (!['GET', 'HEAD'].includes(event.method)) {
    setResponseHeader(event, 'Allow', 'GET, HEAD')
    throw createError({ statusCode: 405, statusMessage: 'Explorer is read only' })
  }
  if (Object.keys(getQuery(event)).length) throw createError({ statusCode: 400, statusMessage: 'This endpoint accepts no query parameters' })
  const ev = await readEvidence()
  const declaration = explorerDeclaration(ev?.explorer)
  return {
    state: declaration ? 'published' : 'unavailable',
    evidence: ev?.evidence,
    declaration,
  }
})
