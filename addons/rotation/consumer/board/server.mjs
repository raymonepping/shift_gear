// board/server.mjs — the Secure Door board (prompt 01_09). Dependency-free Node.
//
// Serves one page and the consumer's NON-SECRET status document:
//   GET /                 the page          GET /api/state   status JSON
//   GET /api/events       Server-Sent Events on every status change
//   GET /healthz          liveness          static: /board.css /tokens.css /board.js /fonts/*
// It reads only BOARD_STATUS_FILE (versions, fingerprints, timings, verdicts) and
// its own static files. It can never serve a secret value: it has no access to
// the Agent-rendered snapshot. It never calls Vault.
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const PORT = Number(process.env.BOARD_PORT ?? 8080)
const STATUS_FILE = process.env.BOARD_STATUS_FILE ?? '/status/state.json'
const STATIC_DIR = process.env.BOARD_STATIC_DIR ?? '/opt/board/static'
const FONT_DIR = process.env.BOARD_FONT_DIR ?? '/opt/board/fonts'
const WATCH_MS = Number(process.env.BOARD_WATCH_MS ?? 500)

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

export function readStatus(file = STATUS_FILE) {
  try {
    const raw = fs.readFileSync(file, 'utf8')
    const doc = JSON.parse(raw)
    return { ok: true, doc, raw }
  } catch {
    return { ok: false, doc: null, raw: null }
  }
}

const clients = new Set()
let lastRaw = null

function broadcast() {
  const { ok, raw } = readStatus()
  if (!ok || raw === lastRaw) return
  lastRaw = raw
  for (const res of clients) res.write(`event: state\ndata: ${raw.replace(/\n/g, '')}\n\n`)
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
    const { ok, raw } = readStatus()
    res.writeHead(ok ? 200 : 503, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...SECURITY_HEADERS })
    res.end(ok ? raw : '{"error":"status not available yet"}')
    return
  }
  if (p === '/api/events') {
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive', ...SECURITY_HEADERS })
    res.write('retry: 2000\n\n')
    const { ok, raw } = readStatus()
    if (ok) res.write(`event: state\ndata: ${raw.replace(/\n/g, '')}\n\n`)
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
  server.listen(port, () => console.log(`${new Date().toISOString()} INFO  [board] listening on :${port} status=${STATUS_FILE}`))
  const timer = setInterval(broadcast, WATCH_MS)
  const stop = () => { clearInterval(timer); for (const c of clients) c.end(); server.close(() => process.exit(0)) }
  process.on('SIGTERM', stop)
  process.on('SIGINT', stop)
  return server
}

// Run as a program (not when imported by the tests). ConfigMap files are
// symlinks, so compare real paths rather than the raw argv/URL strings.
const entry = process.argv[1] ? fs.realpathSync(process.argv[1]) : ''
if (entry && entry === fs.realpathSync(fileURLToPath(import.meta.url))) start()
