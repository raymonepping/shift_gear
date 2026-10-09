# policies/platform/sg-agent-demo.hcl
# Vault Agent sidecar demo pod. Reads secrets from the agent/ sub-path.
# Token comes from Kubernetes auth auto-auth; renewed by the agent.
path "kv/data/shift-gear/agent/*" {
  capabilities = ["read"]
}
path "kv/metadata/shift-gear/agent/*" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
