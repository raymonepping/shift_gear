import fs from 'node:fs'
import https from 'node:https'
import { createLocalJWKSet, jwtVerify } from 'jose'
import { logoutSubject } from '../../shared/logout-claims'
import { invalidateSubject } from './session'

const replay = new Map<string, number>()
let keySet: ReturnType<typeof createLocalJWKSet> | undefined
let keyExpiry = 0

export async function backchannel(token: string) {
  const cfg = useRuntimeConfig()
  const issuer = String(cfg.keycloakLogoutUrl).split('/protocol/')[0]!
  if (!keySet || Date.now() >= keyExpiry) {
    const keys = await new Promise<Parameters<typeof createLocalJWKSet>[0]>((resolve, reject) => {
      const req = https.get(String(cfg.keycloakJwksUrl), { ca: fs.readFileSync(String(cfg.vaultCaFile)), timeout: 5000 }, (res) => {
        let raw = ''
        res.on('data', (chunk) => { raw += chunk; if (raw.length > 262144) req.destroy(new Error('key set too large')) })
        res.on('end', () => {
          try { if (res.statusCode !== 200) throw new Error('keys unavailable'); resolve(JSON.parse(raw)) } catch (error) { reject(error) }
        })
      })
      req.on('timeout', () => req.destroy(new Error('keys unavailable')))
      req.on('error', reject)
    })
    keySet = createLocalJWKSet(keys)
    keyExpiry = Date.now() + 60000
  }
  const { payload } = await jwtVerify(token, keySet, { issuer, audience: 'vault', algorithms: ['RS256'], maxTokenAge: '120s' })
  const subject = logoutSubject(payload)
  for (const [id, expiry] of replay) if (expiry <= Date.now()) replay.delete(id)
  if (replay.has(payload.jti!) || replay.size >= 2048) throw new Error('replayed logout')
  replay.set(payload.jti!, Date.now() + 125000)
  await invalidateSubject(issuer, subject)
}
