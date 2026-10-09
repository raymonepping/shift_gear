// collector/server.mjs — Shift Gear audit collector.
//
// Ingest: a TCP listener for Vault's `socket` audit device. Vault writes one
// JSON object per line, per request and per response. The collector keeps
// the fields the console shows in a bounded in-memory ring buffer. HMAC'd
// values stay HMAC'd: it stores what Vault sent and lifts out only Vault's own
// plain fields. It never logs entry contents.
//
// It must never slow Vault down: lines are parsed on arrival, the buffer is
// bounded (the oldest entry is dropped and counted when it is full), and a
// malformed line is counted and skipped.
//
// Read side: HTTP on READ_PORT with GET /audit (the console's AuditResponse
// shape, newest first, ?limit=N capped at 500) and GET /healthz.
// Counters start at zero when the process starts.
//
// No dependencies: Node's standard library only.
import net from 'node:net'
import http from 'node:http'

const INGEST_PORT = Number(process.env.INGEST_PORT ?? 9090)
const READ_PORT = Number(process.env.READ_PORT ?? 8080)
const CAPACITY = Number(process.env.CAPACITY ?? 1000)
const MAX_LINE = 1024 * 1024 // a single audit line larger than 1 MiB is dropped

const ring = new Array(CAPACITY)
let head = 0 // next write position
let size = 0
let seq = 0

const stats = {
  listening: false,
  connections: 0,
  received: 0,
  stored: 0,
  dropped: 0,
  malformed: 0,
  startedAt: new Date().toISOString(),
  lastEntryAt: null,
}

// Names of HMAC'd values in an audit record: strings Vault prefixed with
// "hmac-sha256:". Only the field paths are kept, never the values.
function hmacFields(obj, prefix = '', out = []) {
  if (out.length >= 20 || obj === null || typeof obj !== 'object') return out
  for (const [k, v] of Object.entries(obj)) {
    const path = prefix ? `${prefix}.${k}` : k
    if (typeof v === 'string' && v.startsWith('hmac-sha256:')) out.push(path)
    else if (typeof v === 'object') hmacFields(v, path, out)
    if (out.length >= 20) break
  }
  return out
}

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
    time: e.time ?? null,
    type: e.type ?? null,
    operation: req.operation ?? null,
    namespace: req.namespace?.path ?? '',
    path: req.path ?? '',
    displayName: e.auth?.display_name ?? null,
    policies: Array.isArray(e.auth?.policies) ? e.auth.policies : [],
    error: e.error ? String(e.error) : null,
    hmacFields: [
      ...hmacFields(e.auth ?? {}, 'auth'),
      ...hmacFields(req.data ?? {}, 'request.data'),
      ...hmacFields(e.response?.data ?? {}, 'response.data'),
    ].slice(0, 20),
  }
}

function store(row) {
  if (size === CAPACITY) stats.dropped += 1
  else size += 1
  seq += 1
  ring[head] = { id: String(seq), ...row }
  head = (head + 1) % CAPACITY
  stats.stored = size
}

function newest(limit) {
  const out = []
  for (let i = 1; i <= Math.min(limit, size); i += 1) {
    out.push(ring[(head - i + CAPACITY) % CAPACITY])
  }
  return out
}

const ingest = net.createServer((sock) => {
  stats.connections += 1
  let buf = ''
  sock.setEncoding('utf8')
  sock.on('data', (chunk) => {
    buf += chunk
    let nl
    while ((nl = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, nl)
      buf = buf.slice(nl + 1)
      if (!line.trim()) continue
      stats.received += 1
      const row = parse(line)
      if (!row) {
        stats.malformed += 1
        continue
      }
      stats.lastEntryAt = new Date().toISOString()
      store(row)
    }
    if (buf.length > MAX_LINE) {
      stats.malformed += 1
      buf = ''
    }
  })
  sock.on('close', () => {
    stats.connections -= 1
  })
  sock.on('error', () => {}) // a reset connection is normal when Vault restarts
})
ingest.listen(INGEST_PORT, () => {
  stats.listening = true
})

const reader = http.createServer((req, res) => {
  const url = new URL(req.url ?? '/', 'http://collector')
  if (req.method !== 'GET') {
    res.writeHead(405).end()
    return
  }
  if (url.pathname === '/healthz') {
    res.writeHead(stats.listening ? 200 : 503, { 'content-type': 'text/plain' })
    res.end(stats.listening ? 'ok\n' : 'not listening\n')
    return
  }
  if (url.pathname === '/audit') {
    const raw = Number.parseInt(url.searchParams.get('limit') ?? '200', 10)
    const limit = Number.isFinite(raw) ? Math.max(0, Math.min(raw, 500)) : 200
    const body = {
      collector: {
        listening: stats.listening,
        connections: stats.connections,
        received: stats.received,
        stored: stats.stored,
        dropped: stats.dropped,
        malformed: stats.malformed,
        startedAt: stats.startedAt,
        lastEntryAt: stats.lastEntryAt,
      },
      entries: newest(limit),
    }
    res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
    res.end(JSON.stringify(body))
    return
  }
  res.writeHead(404).end()
})
reader.listen(READ_PORT)

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    ingest.close()
    reader.close()
    process.exit(0)
  })
}
