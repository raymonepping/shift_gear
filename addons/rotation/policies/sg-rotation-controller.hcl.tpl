# sg-rotation-controller — the KV rotation controller (the add-on's runtime writer).
# Rendered by addons/rotation/terraform/vault.tf from rotation.yaml.
# Lives in Vault namespace shift-gear, so paths are namespace-relative.

# Onboard + rotate (CAS write), compare fingerprints (read), recover
# unrecorded versions (read by version). Never delete or destroy.
path "${mount}/data/${prefix}/*" {
  capabilities          = ["create", "update", "read", "list", "subscribe"]
  subscribe_event_types = ["kv-v2/*"]
}

# Settings (max_versions, cas_required), history records and summary keys in
# custom metadata; reconcile = enforcement layer 1. Never delete.
path "${mount}/metadata/${prefix}/*" {
  capabilities          = ["create", "read", "update", "patch", "list", "subscribe"]
  subscribe_event_types = ["kv-v2/*"]
}
%{ for p in watched_paths ~}

# Watched for the event cascade: version only (metadata) and events — no data read.
path "${mount}/metadata/${p}" {
  capabilities          = ["read", "list", "subscribe"]
  subscribe_event_types = ["kv-v2/*"]
}
path "${mount}/data/${p}" {
  capabilities          = ["list", "subscribe"]
  subscribe_event_types = ["kv-v2/*"]
}
%{ endfor ~}

# Vault event notifications (the vault-events sidecar uses this token).
path "sys/events/subscribe/kv-v2/*" {
  capabilities = ["read"]
}
