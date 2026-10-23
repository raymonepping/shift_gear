# Dedicated fixtures: no proof rotates the application's app-data key.
resource "vault_transit_secret_backend_key" "component_proof" {
  namespace              = vault_namespace.shift_gear.path_fq
  backend                = vault_mount.transit.path
  name                   = "sg-component-proof"
  type                   = "aes256-gcm96"
  exportable             = false
  allow_plaintext_backup = false
  deletion_allowed       = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_pki_secret_backend_role" "component_proof" {
  namespace                   = vault_namespace.shift_gear.path_fq
  backend                     = vault_mount.pki_int.path
  name                        = "sg-component-proof"
  ttl                         = 60
  max_ttl                     = 60
  allow_any_name              = false
  allow_localhost             = false
  allow_ip_sans               = false
  allow_wildcard_certificates = false
  allowed_domains             = ["proof.sg-workloads.svc.cluster.local"]
  allow_bare_domains          = true
  allow_subdomains            = false
  key_usage                   = ["DigitalSignature"]
  ext_key_usage               = ["ClientAuth"]
  no_store                    = false
}

resource "vault_policy" "component_proof" {
  name   = "sg-component-proof"
  policy = file("${path.root}/../../policies/platform/sg-component-proof.hcl")
}

resource "vault_token_auth_backend_role" "component_proof" {
  role_name               = "sg-component-proof"
  allowed_policies        = [vault_policy.component_proof.name]
  orphan                  = false
  renewable               = false
  token_explicit_max_ttl  = 300
  token_no_default_policy = true
}
