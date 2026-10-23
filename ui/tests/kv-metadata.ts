// Host-only proof helper: return version metadata, never a KV payload.
import https from 'node:https'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { ROOT } from './users'
import { BASE } from './auth'

export function appConfigVersion(): Promise<number> {
  const domain = new URL(BASE).hostname.replace(/^shiftgear\./, '')
  return new Promise((resolveVersion, reject) => {
    const req = https.get(`https://vault.${domain}/v1/kv/metadata/shift-gear/config/app-config`, {
      ca: readFileSync(resolve(ROOT, '.secrets/tls/pub/ca.pem')),
      headers: { 'X-Vault-Token': readFileSync(resolve(ROOT, '.secrets/tokens/ansible-platform'), 'utf8').trim(), 'X-Vault-Namespace': 'shift-gear' },
      timeout: 5000,
    }, res => {
      let raw = ''
      res.on('data', chunk => { raw += chunk; if (raw.length > 262144) req.destroy(new Error('metadata exceeds bound')) })
      res.on('end', () => {
        try {
          const version = JSON.parse(raw).data.current_version
          if (res.statusCode !== 200 || !Number.isInteger(version)) throw new Error('metadata unavailable')
          resolveVersion(version)
        } catch { reject(new Error('metadata unavailable')) }
      })
    })
    req.on('timeout', () => req.destroy(new Error('metadata timeout')))
    req.on('error', () => reject(new Error('metadata transport failed')))
  })
}
