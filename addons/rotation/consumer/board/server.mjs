// board/server.mjs — the Secure Door board (prompts 01_09, 01_10). Dependency-free Node.
//
// Serves one page and the two parties' NON-SECRET status documents, merged:
//   GET /                 the page          GET /api/state   {verifier, client} JSON
//   GET /api/events       Server-Sent Events on every status change
//   GET /healthz          liveness          static: /board.css /tokens.css /board.js /fonts/*
// It fetches BOARD_SOURCES ({"verifier": url, "client": url}, each party's
// /status on 9090: versions, fingerprints, timings, verdicts) and serves its own
// static files. It can never serve a secret value: it has no access to either
// party's Agent-rendered snapshot. It never calls Vault.
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const PORT = Number(process.env.BOARD_PORT ?? 8080)
const SOURCES = JSON.parse(process.env.BOARD_SOURCES ?? '{"verifier":"http://door-verifier:9090/status","client":"http://door-client:9090/status"}')
const STATIC_DIR = process.env.BOARD_STATIC_DIR ?? '/opt/board/static'
const FONT_DIR = process.env.BOARD_FONT_DIR ?? '/opt/board/fonts'
const WATCH_MS = Number(process.env.BOARD_WATCH_MS ?? 1000)
const FETCH_TIMEOUT_MS = Number(process.env.BOARD_FETCH_TIMEOUT_MS ?? 2000)
const STATIC = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/index.html': ['index.html', 'text/html; charset=utf-8'],
  '/board.css': ['board.css', 'text/css; charset=utf-8'],
  '/tokens.css': ['tokens.css', 'text/css; charset=utf-8'],
  '/board.js': ['board.js', 'text/javascript; charset=utf-8'],
}
const FONTS = {
  '/fonts/hanken-grotesk.woff2': 'hanken-grotesk.woff2',
  '/fonts/jetbrains-mono.woff2': 'jetbrains-mono.woff2',
}
const SECURITY_HEADERS = {
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Cross-Origin-Resource-Policy': 'same-origin',
}

// One party's status, or why it is missing. A referenced timer aborts the
// fetch (AbortSignal.timeout alone can fail to fire on a hung socket).
async function fetchParty(url) {
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS)
  try {
    const res = await fetch(url, { signal: ctrl.signal, headers: { accept: 'application/json' } })
    if (!res.ok) return { doc: null, error: `status ${res.status}` }
    return { doc: await res.json(), error: null }
  } catch (err) {
    return { doc: null, error: err?.name === 'AbortError' ? 'timed out' : 'unreachable' }
  } finally {
    clearTimeout(timer)
  }
}

// Merge: the last good document per party is kept (marked with the fetch
// error) so a restarting party shows as "not answering", not as blank.
const parties = Object.fromEntries(Object.keys(SOURCES).map((k) => [k, { doc: null, error: 'not fetched yet', at: null }]))
let merged = null
let mergedKey = null

export async function refresh() {
  const results = await Promise.all(Object.entries(SOURCES).map(async ([k, url]) => [k, await fetchParty(url)]))
  const now = new Date().toISOString()
  for (const [k, r] of results) {
    if (r.doc) parties[k] = { doc: r.doc, error: null, at: now }
    else parties[k] = { ...parties[k], error: r.error }
  }
  const doc = { schema: 2, generated_at: now, secret: null, parties: {} }
  for (const [k, p] of Object.entries(parties)) {
    doc.secret ??= p.doc?.secret ?? null
    doc.parties[k] = { answering: p.error === null, error: p.error, fetched_at: p.at, status: p.doc }
  }
  merged = Object.values(parties).some((p) => p.doc) ? doc : null
  // Change detection ignores the timestamps that move on every fetch.
  const key = merged ? JSON.stringify(merged, (k, v) => (k === 'generated_at' || k === 'fetched_at' ? undefined : v)) : null
  const changed = key !== mergedKey
  mergedKey = key
  return changed
}

export function state() { return merged }

const clients = new Set()
const frame = (doc) => `event: state\ndata: ${JSON.stringify(doc)}\n\n`

async function tick() {
  if (await refresh() && merged) for (const res of clients) res.write(frame(merged))
}

export function handler(req, res) {
  const url = new URL(req.url ?? '/', 'http://board.local')
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { Allow: 'GET, HEAD', ...SECURITY_HEADERS }).end()
    return
  }
  const p = url.pathname
  if (p === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json', ...SECURITY_HEADERS }).end('{"ok":true}')
    return
  }
  if (p === '/api/state') {
    res.writeHead(merged ? 200 : 503, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...SECURITY_HEADERS })
    res.end(merged ? JSON.stringify(merged) : '{"error":"no party has answered yet"}')
    return
  }
  if (p === '/api/events') {
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive', ...SECURITY_HEADERS })
    res.write('retry: 2000\n\n')
    if (merged) res.write(frame(merged))
    clients.add(res)
    const ping = setInterval(() => res.write(': ping\n\n'), 15000)
    req.on('close', () => { clearInterval(ping); clients.delete(res) })
    return
  }
  if (STATIC[p]) {
    const [file, type] = STATIC[p]
    return sendFile(res, path.join(STATIC_DIR, file), type)
  }
  if (FONTS[p]) return sendFile(res, path.join(FONT_DIR, FONTS[p]), 'font/woff2', 'public, max-age=86400')
  res.writeHead(404, { 'Content-Type': 'application/json', ...SECURITY_HEADERS }).end('{"error":"not found"}')
}

function sendFile(res, file, type, cache = 'no-cache') {
  fs.readFile(file, (err, body) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'application/json', ...SECURITY_HEADERS }).end('{"error":"not found"}')
      return
    }
    res.writeHead(200, { 'Content-Type': type, 'Cache-Control': cache, ...SECURITY_HEADERS }).end(body)
  })
}

export function start(port = PORT) {
  const server = http.createServer(handler)
  server.listen(port, () => console.log(`${new Date().toISOString()} INFO  [board] listening on :${port} sources=${Object.keys(SOURCES).join(',')}`))
  let running = false
  const timer = setInterval(() => { if (!running) { running = true; tick().finally(() => { running = false }) } }, WATCH_MS)
  tick()
  const stop = () => { clearInterval(timer); for (const c of clients) c.end(); server.close(() => process.exit(0)) }
  process.on('SIGTERM', stop)
  process.on('SIGINT', stop)
  return server
}

// Run as a program (not when imported by the tests). ConfigMap files are
// symlinks, so compare real paths rather than the raw argv/URL strings.
const entry = process.argv[1] ? fs.realpathSync(process.argv[1]) : ''
if (entry && entry === fs.realpathSync(fileURLToPath(import.meta.url))) start()
