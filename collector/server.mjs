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
// shape, newest first, ?limit=N capped at 500), GET /archive and GET /healthz.
// The separate archive commits a narrower metadata projection to bounded disk;
// a numeric-only metrics listener uses METRICS_PORT. Queued records are volatile.
// Counters start at zero when the process starts.
//
// No dependencies: Node's standard library only.
import net from 'node:net'
import http from 'node:http'
import { randomUUID } from 'node:crypto'
import { lineDecoder } from './lines.mjs'
import { parse } from './projection.mjs'
import { MetadataArchive } from './archive.mjs'
import { metrics } from './metrics.mjs'

const INGEST_PORT = Number(process.env.INGEST_PORT ?? 9090)
const READ_PORT = Number(process.env.READ_PORT ?? 8080)
const METRICS_PORT = Number(process.env.METRICS_PORT ?? 8081)
const archive = new MetadataArchive(process.env.ARCHIVE_DIR, {
  maxBytes: Number(process.env.ARCHIVE_MAX_BYTES ?? 64 * 1024 * 1024),
  retentionMs: Number(process.env.ARCHIVE_RETENTION_SECONDS ?? 7 * 86400) * 1000,
})
await archive.init()
const maintenance = setInterval(() => archive.maintain(), 30000)
maintenance.unref()
const CAPACITY = Number(process.env.CAPACITY ?? 1000)
const MAX_LINE = 1024 * 1024 // a single audit line larger than 1 MiB is dropped

const ring = new Array(CAPACITY)
let head = 0 // next write position
let size = 0
let seq = 0

const instanceId = randomUUID()
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


function store(row) {
  if (size === CAPACITY) stats.dropped += 1
  else size += 1
  seq += 1
  ring[head] = { id: `${instanceId}:${seq}`, ...row }
  archive.append(ring[head])
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
  sock.setEncoding('utf8')
  const consume = lineDecoder((line) => {
    stats.received += 1
    const row = parse(line)
    if (!row) { stats.malformed += 1; return }
    stats.lastEntryAt = new Date().toISOString()
    store(row)
  }, () => { stats.malformed += 1 }, MAX_LINE)
  sock.on('data', consume)
  sock.on('close', () => {
    stats.connections -= 1
  })
  sock.on('error', () => {}) // a reset connection is normal when Vault restarts
})
ingest.listen(INGEST_PORT, () => {
  stats.listening = true
})

const reader = http.createServer(async (req, res) => {
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
  if (url.pathname === '/archive') {
    try {
      if (!archive.status().enabled || !archive.status().available) throw new Error('unavailable')
      const entries = await archive.newest(200)
      res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
      res.end(JSON.stringify({ archive: archive.status(), entries }))
    } catch {
      res.writeHead(503, { 'content-type': 'application/json', 'cache-control': 'no-store' })
      res.end(JSON.stringify({ archive: archive.status(), entries: [] }))
    }
    return
  }
  if (url.pathname === '/audit') {
    const raw = Number.parseInt(url.searchParams.get('limit') ?? '200', 10)
    const limit = Number.isFinite(raw) ? Math.max(0, Math.min(raw, 500)) : 200
    const body = {
      collector: {
        instanceId,
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
const metricServer = http.createServer((req, res) => {
  if (req.method !== 'GET') { res.writeHead(405, { Allow: 'GET' }).end(); return }
  if (req.url !== '/metrics') { res.writeHead(404).end(); return }
  res.writeHead(200, { 'content-type': 'text/plain; version=0.0.4; charset=utf-8', 'cache-control': 'no-store' })
  res.end(metrics(stats, archive.status()))
})
metricServer.listen(METRICS_PORT)

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, async () => {
    clearInterval(maintenance)
    ingest.close(); reader.close(); metricServer.close()
    const deadline = setTimeout(() => process.exit(1), 5000)
    try { await archive.close(); clearTimeout(deadline); process.exit(0) } catch { process.exit(1) }
  })
}
