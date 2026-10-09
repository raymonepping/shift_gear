# deploy/seal-agent/agent.hcl
# Vault Agent — seal agent for the Shift Gear cluster.
# Authenticates with AppRole on the seal Vault; proxies every transit seal
# request from the cluster Vault pods, injecting its own token (force).
# The mTLS listener requires a client certificate from the project CA — only
# pods with the vault-tls Secret can reach it (enforced by NetworkPolicy AND
# by the certificate requirement).
#
# Ported from golden_ticket/ansible/roles/seal_agent/templates/agent.hcl.j2,
# adapted for OpenShift: credentials are in a Kubernetes Secret mounted read-only,
# no file system writes needed.

pid_file = "/tmp/vault-agent.pid"

vault {
  address = "https://vault-seal.sg-vault-seal.svc:8200"
  ca_cert = "/vault/userconfig/seal-agent-tls/ca.crt"
}

auto_auth {
  method "approle" {
    mount_path  = "auth/approle"
    min_backoff = "2s"
    max_backoff = "30s"
    config = {
      role_id_file_path                   = "/vault/approle/role-id"
      secret_id_file_path                 = "/vault/approle/secret-id"
      # Keep the file after reading — the rotator CronJob replaces it in-place.
      remove_secret_id_file_after_reading = false
    }
  }
}

# Every proxied request carries the agent's token regardless of what the
# client sent. This is the "no seal token" guarantee — the Vault pods present
# no token; the agent injects its own automatically.
api_proxy {
  use_auto_auth_token = "force"
}

# mTLS listener: the agent validates the client's certificate against the
# project CA. Only Vault pods with the vault-tls Secret can connect.
listener "tcp" {
  address                            = "0.0.0.0:8200"
  tls_cert_file                      = "/vault/userconfig/seal-agent-tls/tls.crt"
  tls_key_file                       = "/vault/userconfig/seal-agent-tls/tls.key"
  tls_client_ca_file                 = "/vault/userconfig/seal-agent-tls/ca.crt"
  tls_require_and_verify_client_cert = true
  tls_min_version                    = "tls12"
}
