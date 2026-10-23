auto_auth {
  method "kubernetes" {
    namespace = "shift-gear"
    mount_path = "auth/kubernetes"
    min_backoff = "1s"
    max_backoff = "10s"
    config = {
      role = "sg-agent-db"
      token_path = "/var/run/sg-agent/token"
    }
  }
}
vault {
  address = "https://vault-active.sg-vault.svc:8200"
  ca_cert = "/vault/ca/ca.pem"
  namespace = "shift-gear"
}
template {
  source = "/vault/config/pgpass.ctmpl"
  destination = "/vault/secrets/pgpass"
  perms = "0600"
  backup = false
  error_on_missing_key = true
}
