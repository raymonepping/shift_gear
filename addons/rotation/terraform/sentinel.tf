# Enforcement layer 3 (ADR D18): a Sentinel Endpoint Governing Policy on the
# managed prefix. ACL alone cannot stop a token that legitimately holds broad
# KV rights (core sg-engineer, sg-ansible-platform), nor inspect a value. The
# EGP is rendered from rotation.yaml, so policy-as-code has one source.
# sg-tf-platform may manage sys/policies/egp/sg-rotation-* only.

locals {
  # The generator's alphabet as a Sentinel regex (mirrors generators.py).
  charset_pattern = {
    alnum = "^[A-Za-z0-9]+$"
    alpha = "^[A-Za-z]+$"
    hex   = "^[0-9a-f]+$"
    lower = "^[a-z0-9]+$"
  }
  class_chars = {
    lower  = "a-z"
    upper  = "A-Z"
    digit  = "0-9"
    symbol = "_.~!@#%^*+=-" # '-' last: literal inside a class, no escapes needed
  }

  egp_types = {
    for name, t in local.rotation.types : name => {
      min_length = t.policy.min_length
      pattern = (
        t.generator.kind == "chars" ? local.charset_pattern[lookup(t.generator, "charset", "alnum")] :
        t.generator.kind == "bytes" ? (lookup(t.generator, "encoding", "base64url") == "hex" ? "^[0-9a-f]+$" : "^[A-Za-z0-9_-]+$") :
        "^[${join("", [for c in sort(lookup(t.generator, "classes", ["lower", "upper", "digit", "symbol"])) : local.class_chars[c] if c != "symbol"])}${contains(lookup(t.generator, "classes", ["lower", "upper", "digit", "symbol"]), "symbol") ? local.class_chars["symbol"] : ""}]+$"
      )
    }
  }
}

resource "vault_egp_policy" "kv_rotation" {
  count     = var.sentinel_enabled ? 1 : 0
  namespace = var.vault_namespace
  name      = "sg-rotation-kv"
  paths = [
    "${local.mount}/data/${local.prefix}/*",
    "${local.mount}/metadata/${local.prefix}/*",
  ]
  enforcement_level = "hard-mandatory"
  policy = templatefile("${path.module}/../sentinel/kv-rotation.sentinel.tpl", {
    mount           = local.mount
    prefix          = local.prefix
    vault_namespace = var.vault_namespace
    k8s_namespace   = var.namespace
    types           = local.egp_types
  })
}
