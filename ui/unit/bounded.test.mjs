import test from 'node:test'
import assert from 'node:assert/strict'
import https from 'node:https'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { boundedJson } from '../server/utils/bounded-json.ts'

test('HTTPS observer rejects oversized and slow streams and verifies certificates', async () => {
  const folder = mkdtempSync(join(tmpdir(), 'sg-observer-'))
  let server
  try {
    execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', join(folder, 'key'), '-out', join(folder, 'cert'), '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost'], { stdio: 'ignore' })
    const cert = readFileSync(join(folder, 'cert'))
    server = https.createServer({ key: readFileSync(join(folder, 'key')), cert }, (req, res) => {
      if (req.url === '/large') { res.end('x'.repeat(65537)); return }
      if (req.url === '/slow') { res.writeHead(200); res.write('{'); return }
      if (req.url === '/redirect') { res.writeHead(302, { location: 'https://untrusted.invalid/' }); res.end('{}'); return }
      res.end('{"ready":true}')
    })
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
    const base = `https://localhost:${server.address().port}`
    assert.deepEqual(await boundedJson(base, cert), { status: 200, json: { ready: true } })
    await assert.rejects(boundedJson(base, Buffer.from('invalid CA')))
    await assert.rejects(boundedJson(`${base}/large`, cert), /response limit/)
    const start = Date.now()
    await assert.rejects(boundedJson(`${base}/slow`, cert), /deadline/)
    assert.ok(Date.now() - start < 5000)
    assert.equal((await boundedJson(`${base}/redirect`, cert)).status, 302)
  } finally {
    server?.closeAllConnections()
    await new Promise(resolve => server ? server.close(resolve) : resolve())
    rmSync(folder, { recursive: true, force: true })
  }
})
