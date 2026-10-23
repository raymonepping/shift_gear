import { readFile } from 'node:fs/promises'
import { boundedJson } from './bounded-json'
import { runtimeSource, type RuntimeResponse, type RuntimeSource } from '../../shared/runtime'
import { projectSealAgent, projectVaultHealth, sealMembers, vaultHealthStatus } from '../../shared/seal-chain'

let cached: { until: number; response: RuntimeResponse } | undefined
let pending: Promise<RuntimeResponse> | undefined
const sa = '/var/run/secrets/kubernetes.io/serviceaccount'

export async function readRuntime(): Promise<RuntimeResponse> {
  if (cached && cached.until > Date.now()) return cached.response
  if (pending) return pending
  pending = collect()
  try {
    const response = await pending
    cached = { until: Date.now() + 10000, response }
    return response
  } finally { pending = undefined }
}

async function collect(): Promise<RuntimeResponse> {
  const cfg = useRuntimeConfig()
  async function probe(name: string, owner: string, resource: string, url: string,
    project: (value: Record<string, unknown>) => RuntimeSource['data'], kube = false, vaultHealth = false) {
    try {
      const ca = await readFile(kube ? `${sa}/ca.crt` : cfg.vaultCaFile)
      const token = kube ? (await readFile(`${sa}/token`, 'utf8')).trim() : undefined
      const result = await boundedJson(url, ca, token)
      return runtimeSource(name, owner, resource, vaultHealth ? vaultHealthStatus(result.status) : result.status, result.json, project)
    } catch (error) {
      const failure = error as { message?: string; code?: string }
      const reason: RuntimeSource['reason'] = failure.message === 'deadline' ? 'timeout'
        : failure.message === 'response limit' ? 'too-large'
          : failure.code === 'ENOENT' ? 'configuration'
            : /CERT|TLS|SELF_SIGNED|ISSUER/.test(failure.code ?? '') ? 'tls' : 'connection'
      return runtimeSource(name, owner, resource, 0, null, project, Date.now(), reason)
    }
  }
  const sources = await Promise.all([
    probe('Seal Vault', 'Vault', 'sg-vault-seal/vault-seal',
      'https://vault-seal.sg-vault-seal.svc:8200/v1/sys/health', projectVaultHealth, false, true),
    probe('Seal Agent', 'Terraform', 'sg-vault-seal/seal-agent',
      'https://kubernetes.default.svc/apis/apps/v1/namespaces/sg-vault-seal/deployments/seal-agent', projectSealAgent, true),
    ...sealMembers.map(name => probe(`Vault member ${name}`, 'Vault', `sg-vault/${name}`,
      `https://${name}.vault-internal.sg-vault.svc.cluster.local:8200/v1/sys/health`, projectVaultHealth, false, true)),
    probe('Vault health', 'Vault', 'sg-vault/vault-active', `${cfg.vaultAddr}/v1/sys/health?standbyok=true&perfstandbyok=true`, (raw) => {
      if (typeof raw.sealed !== 'boolean' || typeof raw.initialized !== 'boolean') throw new Error('shape')
      return { sealed: raw.sealed, initialized: raw.initialized, standby: raw.standby === true }
    }),
    probe('Identity discovery', 'Ansible', 'sg-identity/keycloak', String(cfg.keycloakJwksUrl).replace(/protocol\/openid-connect\/certs$/, '.well-known/openid-configuration'), (raw) => {
      if (typeof raw.issuer !== 'string' || typeof raw.authorization_endpoint !== 'string') throw new Error('shape')
      return { discoveryAvailable: true }
    }),
    ...['app-config', 'db-creds'].map((name, index) => probe(`VSO ${name}`, 'Vault Operator', `sg-workloads/${name}`,
      `https://kubernetes.default.svc/apis/secrets.hashicorp.com/v1beta1/namespaces/sg-workloads/${index ? 'vaultdynamicsecrets' : 'vaultstaticsecrets'}/${name}`, (raw) => {
        const metadata = raw.metadata as { name?: string } | undefined
        if (metadata?.name !== name) throw new Error('shape')
        const status = raw.status as { lastGeneration?: number; lastSync?: number; lastRenewalTime?: number } | undefined
        return { generation: typeof status?.lastGeneration === 'number' ? status.lastGeneration : null,
          lastSync: typeof status?.lastSync === 'number' ? status.lastSync : null,
          lastRenewalTime: typeof status?.lastRenewalTime === 'number' ? status.lastRenewalTime : null,
          deliveryCorrelated: false }
      }, true)),
    ...['workload-a', 'workload-b'].map(name => probe(`Consumer ${name}`, 'Terraform', `sg-workloads/${name}`,
      `https://kubernetes.default.svc/apis/apps/v1/namespaces/sg-workloads/deployments/${name}`, (raw) => {
        const metadata = raw.metadata as { name?: string; generation?: number } | undefined
        const status = raw.status as { readyReplicas?: number; updatedReplicas?: number; observedGeneration?: number } | undefined
        if (metadata?.name !== name || !status) throw new Error('shape')
        return { readyReplicas: status.readyReplicas ?? 0, updatedReplicas: status.updatedReplicas ?? 0,
          generationObserved: typeof metadata.generation === 'number' && status.observedGeneration === metadata.generation }
      }, true)),
  ])
  return { sources }
}
