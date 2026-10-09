// server/utils/vault.ts — BFF → Vault calls with the project CA.
// Used for OIDC sign-in and token revocation only.
// All other Vault calls go through the Express API (sg-api).
import fs from 'node:fs'
import https from 'node:https'

let ca: Buffer | undefined

function caCert(file: string): Buffer | undefined {
  if (ca === undefined && fs.existsSync(file)) ca = fs.readFileSync(file)
  return ca
}

export interface VaultReply { status: number; json: unknown }

export function vaultCall(
  method: string,
  path: string,
  opts: { token?: string; body?: unknown; query?: Record<string, string> } = {},
): Promise<VaultReply> {
  const cfg = useRuntimeConfig()
  const url = new URL(`/v1/${path}`, cfg.vaultAddr)
  for (const [k, v] of Object.entries(opts.query ?? {})) url.searchParams.set(k, v)
  const payload = opts.body === undefined ? undefined : JSON.stringify(opts.body)

  return new Promise((resolve, reject) => {
    const req = https.request(
      url,
      {
        method,
        ca: caCert(cfg.vaultCaFile),
        headers: {
          'X-Vault-Namespace': cfg.vaultNamespace,
          ...(opts.token ? { 'X-Vault-Token': opts.token } : {}),
          ...(payload
            ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }
            : {}),
        },
        timeout: 10_000,
      },
      (res) => {
        let raw = ''
        res.setEncoding('utf8')
        res.on('data', (c) => (raw += c))
        res.on('end', () => {
          let json: unknown
          try {
            json = raw ? JSON.parse(raw) : {}
          } catch {
            json = { errors: [raw.slice(0, 200)] }
          }
          resolve({ status: res.statusCode ?? 0, json })
        })
      },
    )
    req.on('timeout', () => req.destroy(new Error('timeout calling Vault')))
    req.on('error', reject)
    if (payload) req.write(payload)
    req.end()
  })
}
