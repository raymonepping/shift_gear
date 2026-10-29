// node --test addons/rotation/consumer/board/server.test.mjs
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import http from 'node:http'

// Two fake parties: their /status documents are whatever the test sets.
const docs = { verifier: null, client: null }
const fake = http.createServer((req, res) => {
  const who = req.url.slice(1).split('/')[0]
  if (!docs[who]) { res.writeHead(503).end(); return }
  res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(docs[who]))
})
await new Promise((r) => fake.listen(0, r))
const fakeBase = `http://127.0.0.1:${fake.address().port}`

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'board-'))
process.env.BOARD_SOURCES = JSON.stringify({ verifier: `${fakeBase}/verifier/status`, client: `${fakeBase}/client/status` })
process.env.BOARD_STATIC_DIR = path.join(path.dirname(new URL(import.meta.url).pathname), 'static')
process.env.BOARD_FONT_DIR = dir
process.env.BOARD_FETCH_TIMEOUT_MS = '500'
const { handler, refresh } = await import('./server.mjs')

const server = http.createServer(handler)
await new Promise((r) => server.listen(0, r))
const base = `http://127.0.0.1:${server.address().port}`
test.after(() => { server.close(); fake.close() })

const get = async (p) => { const r = await fetch(base + p); return { status: r.status, type: r.headers.get('content-type'), body: await r.text(), headers: r.headers } }

test('state is 503 until a party answered, then both are merged and uncached', async () => {
  await refresh()
  assert.equal((await get('/api/state')).status, 503)
  docs.verifier = { schema: 2, role: 'verifier', secret: 'api-key/secure-door', verifier: { mode: 'grace', current_version: 7 } }
  await refresh()
  let r = await get('/api/state')
  assert.equal(r.status, 200)
  let doc = JSON.parse(r.body)
  assert.equal(doc.secret, 'api-key/secure-door')
  assert.equal(doc.parties.verifier.status.verifier.current_version, 7)
  assert.equal(doc.parties.client.answering, false)
  assert.equal(doc.parties.client.status, null)
  assert.equal(r.headers.get('cache-control'), 'no-store')
  docs.client = { schema: 2, role: 'client', client: { version: 7, fingerprint: 'abcdef012345' } }
  await refresh()
  doc = JSON.parse((await get('/api/state')).body)
  assert.equal(doc.parties.client.answering, true)
  assert.equal(doc.parties.client.status.client.version, 7)
})

test('a party that stops answering keeps its last document, marked not answering', async () => {
  docs.client = null
  assert.equal(await refresh(), true)
  const doc = JSON.parse((await get('/api/state')).body)
  assert.equal(doc.parties.client.answering, false)
  assert.equal(doc.parties.client.status.client.version, 7)
  assert.match(doc.parties.client.error, /status 503/)
  assert.equal(await refresh(), false, 'unchanged parties are not a change')
})

test('the page and its assets are served with a strict CSP', async () => {
  const r = await get('/')
  assert.equal(r.status, 200)
  assert.match(r.type, /text\/html/)
  assert.match(r.body, /The door is fictional; the trust decision is real/)
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
  docs.client = { schema: 2, role: 'client', client: { version: 8 } }
  await refresh()
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
