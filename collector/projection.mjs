// Names of HMAC'd values in an audit record: strings Vault prefixed with
// "hmac-sha256:". Only the field paths are kept, never the values.
function hmacFields(obj, prefix = '', out = [], depth = 0) {
  if (depth > 16 || out.length >= 20 || obj === null || typeof obj !== 'object') return out
  for (const [k, v] of Object.entries(obj)) {
    const path = prefix ? `${prefix}.${k}` : k
    if (typeof v === 'string' && v.startsWith('hmac-sha256:')) out.push(path.slice(0, 256))
    else if (typeof v === 'object') hmacFields(v, path, out, depth + 1)
    if (out.length >= 20) break
  }
  return out
}

const text = (value, max = 256) => typeof value === 'string' ? value.slice(0, max) : null

export function parse(line) {
  let e
  try {
    e = JSON.parse(line)
  } catch {
    return null
  }
  if (!e || typeof e !== 'object' || !e.request) return null
  const req = e.request
  return {
    time: text(e.time),
    type: text(e.type),
    operation: text(req.operation),
    namespace: text(req.namespace?.path) ?? '',
    path: text(req.path, 2048) ?? '',
    displayName: text(e.auth?.display_name),
    policies: Array.isArray(e.auth?.policies) ? e.auth.policies.filter(v => typeof v === 'string').slice(0, 64).map(v => v.slice(0, 256)) : [],
    error: text(e.error, 512),
    hmacFields: [
      ...hmacFields(e.auth ?? {}, 'auth'),
      ...hmacFields(req.data ?? {}, 'request.data'),
      ...hmacFields(e.response?.data ?? {}, 'response.data'),
    ].slice(0, 20),
  }
}
