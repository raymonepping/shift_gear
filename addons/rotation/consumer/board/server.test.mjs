// node --test addons/rotation/consumer/board/server.test.mjs
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import http from 'node:http'

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'board-'))
const status = path.join(dir, 'state.json')
process.env.BOARD_STATUS_FILE = status
process.env.BOARD_STATIC_DIR = path.join(path.dirname(new URL(import.meta.url).pathname), 'static')
process.env.BOARD_FONT_DIR = dir
process.env.BOARD_WATCH_MS = '50'
const { handler } = await import('./server.mjs')

const server = http.createServer(handler)
await new Promise((r) => server.listen(0, r))
const base = `http://127.0.0.1:${server.address().port}`
test.after(() => server.close())

const get = async (p) => { const r = await fetch(base + p); return { status: r.status, type: r.headers.get('content-type'), body: await r.text(), headers: r.headers } }

test('state is 503 until the consumer wrote it, then served verbatim and uncached', async () => {
  assert.equal((await get('/api/state')).status, 503)
  fs.writeFileSync(status, JSON.stringify({ schema: 1, consumer: { version: 7, fingerprint: 'abcdef012345' } }))
  const r = await get('/api/state')
  assert.equal(r.status, 200)
  assert.equal(JSON.parse(r.body).consumer.version, 7)
  assert.equal(r.headers.get('cache-control'), 'no-store')
})

test('the page and its assets are served with a strict CSP', async () => {
  const r = await get('/')
  assert.equal(r.status, 200)
  assert.match(r.type, /text\/html/)
  assert.match(r.body, /Fictional door/)
  assert.match(r.headers.get('content-security-policy'), /default-src 'self'/)
  assert.equal((await get('/tokens.css')).status, 200)
  assert.equal((await get('/board.js')).status, 200)
})

test('nothing else is served: traversal, unknown paths and writes are refused', async () => {
  for (const p of ['/../server.mjs', '/static/../server.mjs', '/%2e%2e/server.mjs', '/etc/passwd', '/fonts/../state.json']) {
    assert.equal((await get(p)).status, 404, p)
  }
  const post = await fetch(base + '/api/state', { method: 'POST', body: '{}' })
  assert.equal(post.status, 405)
})

test('server-sent events deliver the current state', async () => {
  fs.writeFileSync(status, JSON.stringify({ schema: 1, consumer: { version: 8 } }))
  const ctrl = new AbortController()
  const res = await fetch(base + '/api/events', { signal: ctrl.signal })
  assert.equal(res.headers.get('content-type'), 'text/event-stream')
  const reader = res.body.getReader()
  let text = ''
  while (!text.includes('"version":8')) text += new TextDecoder().decode((await reader.read()).value)
  assert.match(text, /event: state/)
  ctrl.abort()
})

test('healthz', async () => {
  assert.equal((await get('/healthz')).body, '{"ok":true}')
})
