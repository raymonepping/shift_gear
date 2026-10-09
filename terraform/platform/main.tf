# terraform/platform/main.tf
# Cluster structure inside the Vault Enterprise namespace `shift-gear`:
# namespace, secret engine mounts, transit key, PKI chain, ACL policies,
# the sg-ui token role, and the file audit device.
#
# Ported from golden_ticket/terraform/platform/main.tf, adapted for OpenShift:
# - Provider talks to the cluster through the passthrough Route (CA from .secrets/tls/pub/ca.pem)
# - VAULT_NAMESPACE unset by tf-run.sh (lesson 16 — prevents double-prefix)
# - apps_domain derived from the infra contract (substrate-independent)
# - D10: health data source is OUTSIDE the check block to keep plan exit-code 0
# - D11: kv/ has prevent_destroy AND the token policy denies delete on it

# ── Enterprise Namespace ──────────────────────────────────────────────────────
resource "vault_namespace" "shift_gear" {
  path = "shift-gear"
}

# ── KV v2 — application secrets (values written by Ansible, never Terraform) ─
# prevent_destroy is the first line (D11). The token policy sg-tf-platform
# denies delete on shift-gear/sys/mounts/kv as the second line.
resource "vault_mount" "kv" {
  namespace   = vault_namespace.shift_gear.path_fq
  path        = "kv"
  type        = "kv"
  description = "Shift Gear application secrets — values written by Ansible (sg-ansible-platform)"
  options     = { version = "2" }

  lifecycle {
    prevent_destroy = true
  }
}

# ── Transit — encryption-as-a-service ─────────────────────────────────────────
resource "vault_mount" "transit" {
  namespace   = vault_namespace.shift_gear.path_fq
  path        = "transit"
  type        = "transit"
  description = "Encryption-as-a-service for Shift Gear workloads"
}

resource "vault_transit_secret_backend_key" "app_data" {
  namespace              = vault_namespace.shift_gear.path_fq
  backend                = vault_mount.transit.path
  name                   = "app-data"
  type                   = "aes256-gcm96"
  exportable             = false
  allow_plaintext_backup = false
  deletion_allowed       = false

  lifecycle {
    prevent_destroy = true
  }
}

# ── PKI root CA ───────────────────────────────────────────────────────────────
resource "vault_mount" "pki" {
  namespace   = vault_namespace.shift_gear.path_fq
  path        = "pki"
  type        = "pki"
  description = "Shift Gear PKI root CA (internal key, 10 years)"

  default_lease_ttl_seconds = 315360000 # 10 years
  max_lease_ttl_seconds     = 315360000
}

resource "vault_pki_secret_backend_root_cert" "root" {
  namespace            = vault_namespace.shift_gear.path_fq
  backend              = vault_mount.pki.path
  type                 = "internal"
  common_name          = "Shift Gear Root CA"
  ttl                  = "315360000"
  key_type             = "rsa"
  key_bits             = 4096
  organization         = "Shift Gear"
  country              = "NL"
  exclude_cn_from_sans = true
}

resource "vault_pki_secret_backend_config_urls" "pki" {
  namespace               = vault_namespace.shift_gear.path_fq
  backend                 = vault_mount.pki.path
  issuing_certificates    = ["https://vault.${local.cluster.apps_domain}/v1/shift-gear/pki/ca"]
  crl_distribution_points = ["https://vault.${local.cluster.apps_domain}/v1/shift-gear/pki/crl"]
}

# ── PKI intermediate CA ───────────────────────────────────────────────────────
resource "vault_mount" "pki_int" {
  namespace   = vault_namespace.shift_gear.path_fq
  path        = "pki-int"
  type        = "pki"
  description = "Shift Gear PKI intermediate CA — signed by the root"

  default_lease_ttl_seconds = 3600  # 1 h default; role max_ttl = 4 h
  max_lease_ttl_seconds     = 14400 # 4 h
}

resource "vault_pki_secret_backend_intermediate_cert_request" "pki_int" {
  namespace   = vault_namespace.shift_gear.path_fq
  backend     = vault_mount.pki_int.path
  type        = "internal"
  common_name = "Shift Gear Intermediate CA"
  key_type    = "rsa"
  key_bits    = 4096
}

resource "vault_pki_secret_backend_root_sign_intermediate" "pki_int" {
  namespace            = vault_namespace.shift_gear.path_fq
  backend              = vault_mount.pki.path
  csr                  = vault_pki_secret_backend_intermediate_cert_request.pki_int.csr
  common_name          = "Shift Gear Intermediate CA"
  ttl                  = "157680000" # 5 years
  format               = "pem_bundle"
  exclude_cn_from_sans = true
}

resource "vault_pki_secret_backend_intermediate_set_signed" "pki_int" {
  namespace   = vault_namespace.shift_gear.path_fq
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.pki_int.certificate
}

resource "vault_pki_secret_backend_config_urls" "pki_int" {
  namespace               = vault_namespace.shift_gear.path_fq
  backend                 = vault_mount.pki_int.path
  issuing_certificates    = ["https://vault.${local.cluster.apps_domain}/v1/shift-gear/pki-int/ca"]
  crl_distribution_points = ["https://vault.${local.cluster.apps_domain}/v1/shift-gear/pki-int/crl"]
}

# Issue short-lived client certificates (lesson 24: serverAuth+clientAuth).
resource "vault_pki_secret_backend_role" "internal_client" {
  namespace        = vault_namespace.shift_gear.path_fq
  backend          = vault_mount.pki_int.path
  name             = "internal-client"
  ttl              = 3600  # 1 h
  max_ttl          = 14400 # 4 h
  allow_any_name   = false
  allowed_domains  = ["sg-vault.svc.cluster.local", "sg-workloads.svc.cluster.local", "sg-app.svc.cluster.local"]
  allow_subdomains = true
  key_usage        = ["DigitalSignature", "KeyEncipherment"]
  ext_key_usage    = ["ServerAuth", "ClientAuth"]
  no_store         = true
}

# ── Database mount (Ansible configures the connection in prompt 06) ───────────
resource "vault_mount" "database" {
  namespace   = vault_namespace.shift_gear.path_fq
  path        = "database"
  type        = "database"
  description = "Dynamic database credentials — connection configured by Ansible (sg-ansible-platform)"
}

# ── ACL policies ──────────────────────────────────────────────────────────────
resource "vault_policy" "platform" {
  for_each  = var.platform_policies
  namespace = vault_namespace.shift_gear.path_fq
  name      = each.value
  policy    = file("${path.root}/../../policies/platform/${each.value}.hcl")
}

# ── Token role for the Shift Gear UI / API ────────────────────────────────────
# Lesson 31: the API pod reaches Vault through the passthrough Route. Vault sees
# the pod's IP (10.217.x.x — pod CIDR). `token_bound_cidrs` is set to the pod
# CIDR from the contract. Verify with: vault token lookup <token>; check the
# issued address against the configured CIDR.
resource "vault_token_auth_backend_role" "sg_ui" {
  namespace               = vault_namespace.shift_gear.path_fq
  role_name               = "sg-ui"
  allowed_policies        = [vault_policy.platform["sg-api"].name]
  orphan                  = true
  renewable               = true
  token_period            = 2592000 # 30 days
  token_no_default_policy = true
  token_bound_cidrs       = [local.cluster.pod_cidr]
}

# ── File audit device (stdout) ────────────────────────────────────────────────
# Enabled at root, audits all requests. The socket device (for the API
# evidence collector) is Ansible's (prompt 06) — it needs the collector running.
resource "vault_audit" "file" {
  type        = "file"
  description = "File audit device — writes JSON to stdout for OpenShift log aggregation"
  options = {
    file_path = "stdout"
  }
}

# ── Continuous health assertion (D10) ─────────────────────────────────────────
# The data source is OUTSIDE the check block: a data source inside check is
# re-evaluated at every plan and makes `plan -detailed-exitcode` return 2.
data "http" "cluster_health" {
  url             = "https://vault.${local.cluster.apps_domain}/v1/sys/health?standbyok=true&perfstandbyok=true"
  ca_cert_pem     = try(file("${path.root}/../../.secrets/tls/pub/ca.pem"), null)
  request_headers = {}
}

check "cluster_is_healthy" {
  assert {
    condition     = data.http.cluster_health.status_code == 200
    error_message = "The Vault cluster does not answer healthy (HTTP ${data.http.cluster_health.status_code})."
  }
}

# ── Licence features (D9) ─────────────────────────────────────────────────────
# Read licence metadata to drive licence-aware outputs. Only feature NAMES are
# unmarked with nonsensitive(); the licence string itself is never read here.
data "vault_generic_secret" "license" {
  path = "sys/license/status"
}

locals {
  license_features = toset(
    nonsensitive(
      try(jsondecode(data.vault_generic_secret.license.data_json).autoloaded.features, [])
    )
  )
}

# ── Socket audit device (to the collector the workloads root runs) ────────────
# Feeds the console's Audit page. The file device above stays: Vault blocks a
# request only when every audit device fails, so stdout keeps Vault serving
# while the collector restarts. Vault refuses to enable a socket device it
# cannot reach; the workloads root waits for the collector's rollout first.
data "terraform_remote_state" "workloads" {
  backend = "local"
  config = {
    path = "../../.secrets/terraform/workloads/terraform.tfstate"
  }
}

resource "vault_audit" "socket" {
  type        = "socket"
  path        = "socket"
  description = "Socket audit device: JSON lines to the sg-audit collector (console Audit page)"
  options = {
    address     = try(data.terraform_remote_state.workloads.outputs.audit_collector.ingest_address, "")
    socket_type = "tcp"
    format      = "json"
  }

  lifecycle {
    precondition {
      condition     = try(data.terraform_remote_state.workloads.outputs.audit_collector.ingest_address, "") != ""
      error_message = "The workloads root has no audit_collector output: run 'make workloads' before 'make platform'."
    }
  }
}
