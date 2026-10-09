# terraform/workloads/main.tf
# Workloads layer: Helm releases for the seal Vault and the 3-node Vault
# Enterprise cluster; seal-agent Deployment + Service; seal-rotator CronJob;
# OpenLDAP and Keycloak Deployments, Services, PVCs and NetworkPolicies.
#
# Secret values (TLS certs, licence, AppRole credentials, LDAP and Keycloak
# admin passwords) are created by Ansible and referenced by name only —
# never in state.
# Both Vault releases use wait=false because they cannot become fully ready
# until later Ansible phases run (seal-init, agent, bootstrap).

locals {
  apps_domain = local.cluster.apps_domain
  labels = {
    "app.kubernetes.io/part-of"    = "shift-gear"
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Seal Vault (vault-seal, sg-vault-seal, 1 replica, Shamir 1/1)
# ---------------------------------------------------------------------------
resource "helm_release" "vault_seal" {
  name            = "vault-seal"
  namespace       = "sg-vault-seal"
  repository      = "https://helm.releases.hashicorp.com"
  chart           = "vault"
  version         = var.vault_seal_chart_version
  values          = [file("${path.root}/../../deploy/vault-seal/values.yaml")]
  cleanup_on_fail = true
  # wait=false: the pod cannot be fully ready (readiness path returns 204 for
  # sealed/uninit) until ansible seal-init runs. Ansible asserts readiness.
  wait = false
}

# ---------------------------------------------------------------------------
# Seal Agent Deployment + ConfigMap + Service
# ---------------------------------------------------------------------------

# The agent HCL is a ConfigMap so the pod can mount it read-only.
resource "kubernetes_config_map" "seal_agent_config" {
  metadata {
    name      = "seal-agent-config"
    namespace = "sg-vault-seal"
    labels    = local.labels
  }
  data = {
    "agent.hcl" = file("${path.root}/../../deploy/seal-agent/agent.hcl")
  }
}

# Rotator script as a ConfigMap — the CronJob mounts it as an executable.
resource "kubernetes_config_map" "seal_rotator_script" {
  metadata {
    name      = "seal-rotator-script"
    namespace = "sg-vault-seal"
    labels    = local.labels
  }
  data = {
    "seal-rotate-mint.sh" = file("${path.root}/../../deploy/seal-agent/seal-rotate-mint.sh")
    "seal-rotate.sh"      = file("${path.root}/../../deploy/seal-agent/seal-rotate.sh")
  }
}

resource "kubernetes_deployment" "seal_agent" {
  metadata {
    name      = "seal-agent"
    namespace = "sg-vault-seal"
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "seal-agent"
      }
    }
    template {
      metadata {
        labels = merge(local.labels, {
          "app.kubernetes.io/name" = "seal-agent"
        })
      }
      spec {
        service_account_name = "seal-agent"
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name  = "seal-agent"
          image = "docker.io/hashicorp/vault-enterprise:2.1.0-ent@sha256:12c3ac1469d11da17747927128ed11bce825a012d3ce13b066d0442d0105df0a"
          args  = ["agent", "-config=/vault/config/agent.hcl"]
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          port {
            name           = "https"
            container_port = 8200
            protocol       = "TCP"
          }
          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { memory = "256Mi" }
          }
          volume_mount {
            name       = "config"
            mount_path = "/vault/config"
            read_only  = true
          }
          volume_mount {
            name       = "seal-agent-tls"
            mount_path = "/vault/userconfig/seal-agent-tls"
            read_only  = true
          }
          volume_mount {
            name       = "approle"
            mount_path = "/vault/approle"
            read_only  = true
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.seal_agent_config.metadata[0].name
          }
        }
        volume {
          name = "seal-agent-tls"
          secret {
            secret_name = "seal-agent-tls"
          }
        }
        # seal-agent-approle is written by Ansible (agent phase); optional=true
        # so the Deployment can be created before the secret exists.
        volume {
          name = "approle"
          secret {
            secret_name = "seal-agent-approle"
            optional    = true
          }
        }
      }
    }
  }
  # The agent cannot authenticate until Ansible writes seal-agent-approle
  # (agent phase), which asserts readiness; Terraform must not wait for it.
  wait_for_rollout = false

  timeouts {
    create = "5m"
    update = "5m"
  }
}

resource "kubernetes_service" "seal_agent" {
  metadata {
    name      = "seal-agent"
    namespace = "sg-vault-seal"
    labels    = local.labels
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "seal-agent"
    }
    port {
      name        = "https"
      port        = 8200
      target_port = 8200
      protocol    = "TCP"
    }
  }
}

# ---------------------------------------------------------------------------
# Seal Rotator CronJob
# ---------------------------------------------------------------------------
resource "kubernetes_cron_job_v1" "seal_rotator" {
  metadata {
    name      = "seal-rotator"
    namespace = "sg-vault-seal"
    labels    = local.labels
  }
  spec {
    schedule                      = "0 */6 * * *"
    concurrency_policy            = "Forbid"
    starting_deadline_seconds     = 21600 # a slot missed while the cluster was stopped runs once after resume
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3
    job_template {
      metadata {}
      spec {
        backoff_limit = 2
        template {
          metadata {
            labels = {
              "app.kubernetes.io/name" = "seal-rotator"
            }
          }
          spec {
            service_account_name = "seal-rotator"
            restart_policy       = "Never"
            security_context {
              run_as_non_root = true
              seccomp_profile {
                type = "RuntimeDefault"
              }
            }
            # Step 1 — Vault image (vault CLI; no curl, no jq): log in as the
            # rotator, mint the new secret-id, list the old ones.
            init_container {
              name    = "mint"
              image   = "docker.io/hashicorp/vault-enterprise:2.1.0-ent@sha256:12c3ac1469d11da17747927128ed11bce825a012d3ce13b066d0442d0105df0a"
              command = ["/bin/sh", "/scripts/seal-rotate-mint.sh"]
              env {
                name  = "VAULT_ADDR"
                value = "https://vault-seal.sg-vault-seal.svc:8200"
              }
              env {
                name  = "VAULT_CACERT"
                value = "/vault/userconfig/sg-ca/ca.pem"
              }
              security_context {
                allow_privilege_escalation = false
                run_as_non_root            = true
                capabilities {
                  drop = ["ALL"]
                }
              }
              resources {
                requests = { cpu = "10m", memory = "32Mi" }
                limits   = { memory = "128Mi" }
              }
              volume_mount {
                name       = "scripts"
                mount_path = "/scripts"
                read_only  = true
              }
              volume_mount {
                name       = "sg-ca"
                mount_path = "/vault/userconfig/sg-ca"
                read_only  = true
              }
              volume_mount {
                name       = "rotator-approle"
                mount_path = "/vault/approle"
                read_only  = true
              }
              volume_mount {
                name       = "work"
                mount_path = "/work"
              }
            }
            # Step 2 — the cluster's own cli image (oc + curl): hand the new
            # secret-id to the agent, then destroy the old ones.
            container {
              name    = "rotator"
              image   = "image-registry.openshift-image-registry.svc:5000/openshift/cli:latest"
              command = ["/bin/sh", "/scripts/seal-rotate.sh"]
              env {
                name  = "VAULT_ADDR"
                value = "https://vault-seal.sg-vault-seal.svc:8200"
              }
              env {
                name  = "VAULT_CACERT"
                value = "/vault/userconfig/sg-ca/ca.pem"
              }
              security_context {
                allow_privilege_escalation = false
                run_as_non_root            = true
                capabilities {
                  drop = ["ALL"]
                }
              }
              resources {
                requests = { cpu = "10m", memory = "32Mi" }
                limits   = { memory = "256Mi" }
              }
              volume_mount {
                name       = "scripts"
                mount_path = "/scripts"
                read_only  = true
              }
              volume_mount {
                name       = "sg-ca"
                mount_path = "/vault/userconfig/sg-ca"
                read_only  = true
              }
              volume_mount {
                name       = "work"
                mount_path = "/work"
              }
            }
            volume {
              name = "scripts"
              config_map {
                name         = kubernetes_config_map.seal_rotator_script.metadata[0].name
                default_mode = "0555"
              }
            }
            volume {
              name = "sg-ca"
              config_map {
                name = "sg-ca"
              }
            }
            # seal-rotator-approle is written by Ansible (agent phase)
            volume {
              name = "rotator-approle"
              secret {
                secret_name = "seal-rotator-approle"
                optional    = true
              }
            }
            # Hand-over between the two steps; memory only, gone with the pod.
            volume {
              name = "work"
              empty_dir {
                medium = "Memory"
              }
            }
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Main Vault Enterprise HA cluster (vault, sg-vault, 3 replicas)
# ---------------------------------------------------------------------------
resource "helm_release" "vault" {
  name            = "vault"
  namespace       = "sg-vault"
  repository      = "https://helm.releases.hashicorp.com"
  chart           = "vault"
  version         = var.vault_chart_version
  values          = [file("${path.root}/../../deploy/vault/values.yaml")]
  cleanup_on_fail = true
  # wait=false: pods enter Init (wait-for-seal-vault) until agent phase.
  wait = false

  depends_on = [
    helm_release.vault_seal,
    kubernetes_deployment.seal_agent,
  ]
}

# ---------------------------------------------------------------------------
# Identity NetworkPolicies
# Keycloak: 8443 from the router namespaces AND from sg-vault (OIDC discovery)
# OpenLDAP: 1389 from Keycloak pods AND from sg-vault pods (LDAP auth)
# Management port 9000 is deliberately not permitted by any policy.
# ---------------------------------------------------------------------------

resource "kubernetes_network_policy" "keycloak_ingress" {
  metadata {
    name      = "keycloak-ingress"
    namespace = "sg-identity"
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "keycloak"
      }
    }
    policy_types = ["Ingress"]
    # OpenShift router (reencrypt Route)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "policy-group.network.openshift.io/ingress" = ""
          }
        }
      }
      from {
        namespace_selector {
          match_labels = {
            "policy-group.network.openshift.io/host-network" = ""
          }
        }
      }
      ports {
        port     = 8443
        protocol = "TCP"
      }
    }
    # Vault pods (OIDC discovery + token endpoint)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "sg-vault"
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "vault"
          }
        }
      }
      ports {
        port     = 8443
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy" "openldap_ingress" {
  metadata {
    name      = "openldap-ingress"
    namespace = "sg-identity"
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "openldap"
      }
    }
    policy_types = ["Ingress"]
    # Keycloak pods (LDAP federation sync)
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "keycloak"
          }
        }
      }
      ports {
        port     = 1389
        protocol = "TCP"
      }
    }
    # Vault pods (LDAP auth method)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "sg-vault"
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "vault"
          }
        }
      }
      ports {
        port     = 1389
        protocol = "TCP"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# OpenLDAP
# Runs on port 1389 under OpenShift's arbitrary UID (restricted-v2).
# Image built in-cluster by terraform/foundation BuildConfig from
# deploy/identity/openldap/. Ansible triggers the build via oc start-build.
# Admin password supplied via Secret openldap-admin (Ansible writes it).
# PVC: 1Gi ReadWriteOnce; mdb database files persist across pod restarts.
# ---------------------------------------------------------------------------

resource "kubernetes_persistent_volume_claim" "openldap" {
  # The default storage class binds on first consumer (WaitForFirstConsumer);
  # the pod that consumes this claim is created after it, so do not wait.
  wait_until_bound = false

  metadata {
    name      = "openldap-data"
    namespace = "sg-identity"
    labels    = local.labels
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "1Gi" }
    }
  }
}

resource "kubernetes_service" "openldap" {
  metadata {
    name      = "openldap"
    namespace = "sg-identity"
    labels    = local.labels
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "openldap"
    }
    port {
      name        = "ldap"
      port        = 1389
      target_port = 1389
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_deployment" "openldap" {
  metadata {
    name      = "openldap"
    namespace = "sg-identity"
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "openldap"
      }
    }
    strategy {
      type = "Recreate"
    }
    template {
      metadata {
        labels = merge(local.labels, {
          "app.kubernetes.io/name" = "openldap"
        })
      }
      spec {
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name = "openldap"
          # Image built by the BuildConfig in terraform/foundation; the
          # ImageStream lookup policy (local=true) resolves the short tag.
          # lifecycle.ignore_changes keeps Terraform from replacing the pod
          # if a new build produces a new digest between applies.
          image = "image-registry.openshift-image-registry.svc:5000/sg-identity/openldap:latest"
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          port {
            name           = "ldap"
            container_port = 1389
            protocol       = "TCP"
          }
          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { memory = "256Mi" }
          }
          env {
            name = "LDAP_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = "openldap-admin"
                key  = "password"
              }
            }
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/openldap/data"
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.openldap.metadata[0].name
          }
        }
      }
    }
  }
  wait_for_rollout = false
  timeouts {
    create = "5m"
    update = "5m"
  }
}

# ---------------------------------------------------------------------------
# Keycloak
# Runs on HTTPS port 8443 under restricted-v2. No anyuid — Keycloak 26+
# supports arbitrary UIDs out of the box (runs as 1000 if not overridden,
# but accepts a different UID when started as non-root).
# Image: quay.io/keycloak/keycloak, arm64, pinned by digest.
# Admin credentials from Secret keycloak-admin (Ansible writes it).
# --db=dev-file: embedded H2 on a PVC, sufficient for a local lab.
# For production, swap --db=postgres with an external DB (prompt 06).
# Management port 9000 is not exposed by a Route (operational invariant).
# ---------------------------------------------------------------------------

resource "kubernetes_persistent_volume_claim" "keycloak" {
  # The default storage class binds on first consumer (WaitForFirstConsumer);
  # the pod that consumes this claim is created after it, so do not wait.
  wait_until_bound = false

  metadata {
    name      = "keycloak-data"
    namespace = "sg-identity"
    labels    = local.labels
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "2Gi" }
    }
  }
}

resource "kubernetes_service" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = "sg-identity"
    labels    = local.labels
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "keycloak"
    }
    port {
      name        = "https"
      port        = 8443
      target_port = 8443
      protocol    = "TCP"
    }
    # Management port is intentionally not exposed: no NodePort, no Route.
  }
}

resource "kubernetes_deployment" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = "sg-identity"
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "keycloak"
      }
    }
    strategy {
      type = "Recreate"
    }
    template {
      metadata {
        labels = merge(local.labels, {
          "app.kubernetes.io/name" = "keycloak"
        })
      }
      spec {
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name = "keycloak"
          # quay.io/keycloak/keycloak 26.2.5, multi-arch manifest-list digest (the node selects arm64); verified 2026-10-09.
          # Verify with: oc image info --show-multiarch quay.io/keycloak/keycloak:26.2.5
          image = "quay.io/keycloak/keycloak:26.2.5@sha256:4883630ef9db14031cde3e60700c9a9a8eaf1b5c24db1589d6a2d43de38ba2a9"
          args  = ["start", "--db=dev-file", "--https-port=8443", "--http-enabled=false"]
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          port {
            name           = "https"
            container_port = 8443
            protocol       = "TCP"
          }
          # Management port 9000 is deliberately not declared here so it is
          # never reachable from outside the pod.
          resources {
            requests = { cpu = "200m", memory = "512Mi" }
            limits   = { memory = "1Gi" }
          }
          env {
            name = "KEYCLOAK_ADMIN"
            value_from {
              secret_key_ref {
                name = "keycloak-admin"
                key  = "username"
              }
            }
          }
          env {
            name = "KEYCLOAK_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = "keycloak-admin"
                key  = "password"
              }
            }
          }
          # Hostname must match the Route so that the iss claim is correct.
          env {
            name  = "KC_HOSTNAME"
            value = "keycloak.${local.apps_domain}"
          }
          env {
            name  = "KC_PROXY_HEADERS"
            value = "xforwarded"
          }
          volume_mount {
            name       = "data"
            mount_path = "/opt/keycloak/data"
          }
          volume_mount {
            name       = "keycloak-tls"
            mount_path = "/opt/keycloak/conf/tls"
            read_only  = true
          }
          env {
            name  = "KC_HTTPS_CERTIFICATE_FILE"
            value = "/opt/keycloak/conf/tls/tls.crt"
          }
          env {
            name  = "KC_HTTPS_CERTIFICATE_KEY_FILE"
            value = "/opt/keycloak/conf/tls/tls.key"
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.keycloak.metadata[0].name
          }
        }
        volume {
          name = "keycloak-tls"
          secret {
            # Ansible (sg_identity secrets task) creates keycloak-tls from
            # the project CA-signed cert (.secrets/tls/keycloak.*).
            secret_name = "keycloak-tls"
            optional    = true
          }
        }
      }
    }
  }
  wait_for_rollout = false
  timeouts {
    create = "5m"
    update = "5m"
  }
}

# ---------------------------------------------------------------------------
# PostgreSQL (sg-workloads)
# RHEL9 PostgreSQL 16 image — arm64, runs under restricted-v2 (random UID).
# Admin password from Secret postgres-admin (Ansible creates it).
# PVC 2Gi; db shiftgear + demo table seeded by Ansible configure.
# ---------------------------------------------------------------------------

resource "kubernetes_persistent_volume_claim" "postgres" {
  # The default storage class binds on first consumer (WaitForFirstConsumer);
  # the pod that consumes this claim is created after it, so do not wait.
  wait_until_bound = false

  metadata {
    name      = "postgres-data"
    namespace = "sg-workloads"
    labels    = local.labels
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "2Gi" }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres"
    namespace = "sg-workloads"
    labels    = local.labels
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "postgres"
    }
    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "postgres"
    namespace = "sg-workloads"
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "postgres"
      }
    }
    strategy {
      type = "Recreate"
    }
    template {
      metadata {
        labels = merge(local.labels, {
          "app.kubernetes.io/name" = "postgres"
        })
      }
      spec {
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name = "postgres"
          # registry.redhat.io/rhel9/postgresql-16 — arm64, restricted-v2 safe.
          # Pinned by digest; update by bumping the tag + digest together.
          image = "registry.redhat.io/rhel9/postgresql-16:latest"
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          port {
            name           = "postgres"
            container_port = 5432
            protocol       = "TCP"
          }
          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }
          # Admin password only. The image accepts POSTGRESQL_DATABASE only with a
          # POSTGRESQL_USER/PASSWORD pair, and it resets that user's password on
          # every start, which would undo Vault's rotate-root. The database and
          # vault_admin are created by Ansible (configure).
          env {
            name = "POSTGRESQL_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = "postgres-admin"
                key  = "password"
              }
            }
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/pgsql/data"
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres.metadata[0].name
          }
        }
      }
    }
  }
  wait_for_rollout = false
  timeouts {
    create = "5m"
    update = "5m"
  }
}

# NetworkPolicy: postgres :5432 from workload pods and sg-vault only
resource "kubernetes_network_policy" "postgres_ingress" {
  metadata {
    name      = "postgres-ingress"
    namespace = "sg-workloads"
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "postgres"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {
          match_expressions {
            key      = "app.kubernetes.io/name"
            operator = "In"
            values   = ["workload-a", "workload-b"]
          }
        }
      }
      ports {
        port     = 5432
        protocol = "TCP"
      }
    }
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "sg-vault"
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "vault"
          }
        }
      }
      ports {
        port     = 5432
        protocol = "TCP"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# VSO Resources (sg-workloads)
# VaultConnection → VaultAuth → VaultStaticSecret + VaultDynamicSecret
# All VSO CRDs are applied as kubernetes_manifest resources.
# The CSV gate in sg_prepare guarantees the CRD API is ready before apply.
# ---------------------------------------------------------------------------

# VaultConnection: points at the active Vault service, verifies the project CA.
# sg-ca-secret is created by ansible configure (copies .secrets/tls/pub/ca.pem).
resource "kubernetes_manifest" "vso_connection" {
  manifest = {
    apiVersion = "secrets.hashicorp.com/v1beta1"
    kind       = "VaultConnection"
    metadata = {
      name      = "default"
      namespace = "sg-workloads"
      labels    = local.labels
    }
    spec = {
      address         = "https://vault-active.sg-vault.svc:8200"
      caCertSecretRef = "sg-ca-secret"
      skipTLSVerify   = false
    }
  }
}

# VaultAuth: Kubernetes auth method, shift-gear namespace, role vso-workloads.
resource "kubernetes_manifest" "vso_auth" {
  manifest = {
    apiVersion = "secrets.hashicorp.com/v1beta1"
    kind       = "VaultAuth"
    metadata = {
      name      = "default"
      namespace = "sg-workloads"
      labels    = local.labels
    }
    spec = {
      vaultConnectionRef = "default"
      method             = "kubernetes"
      mount              = "kubernetes"
      namespace          = "shift-gear"
      kubernetes = {
        role           = "vso-workloads"
        serviceAccount = "vso-workloads"
      }
    }
  }
}

# VaultStaticSecret: KV v2 app-config → Secret app-config, rolls workload-a.
resource "kubernetes_manifest" "vso_static_app_config" {
  manifest = {
    apiVersion = "secrets.hashicorp.com/v1beta1"
    kind       = "VaultStaticSecret"
    metadata = {
      name      = "app-config"
      namespace = "sg-workloads"
      labels    = local.labels
    }
    spec = {
      vaultAuthRef = "default"
      type         = "kv-v2"
      mount        = "kv"
      namespace    = "shift-gear"
      path         = "shift-gear/config/app-config"
      refreshAfter = "30s"
      destination = {
        name   = "app-config"
        create = true
      }
      rolloutRestartTargets = [
        { kind = "Deployment", name = "workload-a" }
      ]
    }
  }
}

# VaultDynamicSecret: database creds/demo-reader → Secret db-creds, rolls workload-b.
resource "kubernetes_manifest" "vso_dynamic_db_creds" {
  manifest = {
    apiVersion = "secrets.hashicorp.com/v1beta1"
    kind       = "VaultDynamicSecret"
    metadata = {
      name      = "db-creds"
      namespace = "sg-workloads"
      labels    = local.labels
    }
    spec = {
      vaultAuthRef   = "default"
      mount          = "database"
      namespace      = "shift-gear"
      path           = "creds/demo-reader"
      renewalPercent = 67
      destination = {
        name   = "db-creds"
        create = true
      }
      rolloutRestartTargets = [
        { kind = "Deployment", name = "workload-b" }
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# Workload A — mounts app-config (KV v2), logs key names only
# ---------------------------------------------------------------------------

resource "kubernetes_deployment" "workload_a" {
  metadata {
    name      = "workload-a"
    namespace = "sg-workloads"
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "workload-a"
      }
    }
    template {
      metadata {
        labels = merge(local.labels, {
          "app.kubernetes.io/name" = "workload-a"
        })
        annotations = {
          # SCC hint — not required on OCP 4.11+ but documents intent
          "openshift.io/required-scc" = "restricted-v2"
        }
      }
      spec {
        service_account_name = "vso-workloads"
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name    = "workload-a"
          image   = "registry.access.redhat.com/ubi9/ubi-micro:latest"
          command = ["/bin/sh", "-c"]
          args = [<<-CMD
            echo "workload-a: app-config key names: $$(ls /etc/app-config/ 2>/dev/null | tr '\n' ' ')"
            sleep 86400
          CMD
          ]
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = { cpu = "10m", memory = "16Mi" }
            limits   = { memory = "32Mi" }
          }
          volume_mount {
            name       = "app-config"
            mount_path = "/etc/app-config"
            read_only  = true
          }
        }
        volume {
          name = "app-config"
          secret {
            secret_name = "app-config"
            optional    = true
          }
        }
      }
    }
  }
  wait_for_rollout = false
  timeouts {
    create = "5m"
    update = "5m"
  }

  # VSO restarts this workload when its secret changes (rolloutRestartTargets)
  # by stamping the pod template; that annotation is VSO's, not drift.
  lifecycle {
    ignore_changes = [
      spec[0].template[0].metadata[0].annotations["vso.secrets.hashicorp.com/restartedAt"],
    ]
  }
}

# ---------------------------------------------------------------------------
# Workload B — mounts db-creds (dynamic), runs SELECT, logs count + username
# ---------------------------------------------------------------------------

resource "kubernetes_deployment" "workload_b" {
  metadata {
    name      = "workload-b"
    namespace = "sg-workloads"
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "workload-b"
      }
    }
    template {
      metadata {
        labels = merge(local.labels, {
          "app.kubernetes.io/name" = "workload-b"
        })
        annotations = {
          "openshift.io/required-scc" = "restricted-v2"
        }
      }
      spec {
        service_account_name = "vso-workloads"
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name    = "workload-b"
          image   = "registry.access.redhat.com/ubi9/ubi-micro:latest"
          command = ["/bin/sh", "-c"]
          args = [<<-CMD
            DB_USER=$$(cat /etc/db-creds/username 2>/dev/null || echo "")
            DB_PASS=$$(cat /etc/db-creds/password 2>/dev/null || echo "")
            echo "workload-b: db user=$${DB_USER} (password withheld)"
            PGPASSWORD="$${DB_PASS}" psql -h postgres.sg-workloads.svc -U "$${DB_USER}" -d shiftgear \
              -c "SELECT count(*) FROM demo;" 2>&1 | tail -3 || true
            sleep 300
          CMD
          ]
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { memory = "64Mi" }
          }
          volume_mount {
            name       = "db-creds"
            mount_path = "/etc/db-creds"
            read_only  = true
          }
        }
        volume {
          name = "db-creds"
          secret {
            secret_name = "db-creds"
            optional    = true
          }
        }
      }
    }
  }
  wait_for_rollout = false
  timeouts {
    create = "5m"
    update = "5m"
  }

  # VSO restarts this workload when its secret changes (rolloutRestartTargets)
  # by stamping the pod template; that annotation is VSO's, not drift.
  lifecycle {
    ignore_changes = [
      spec[0].template[0].metadata[0].annotations["vso.secrets.hashicorp.com/restartedAt"],
    ]
  }
}

# ---------------------------------------------------------------------------
# Agent Demo (sg-app) — Vault Agent sidecar that renders a KV secret
# to /vault/secrets/demo-secret without exposing a token to the app.
# The agent authenticates via kubernetes auth (role sg-agent-demo) and
# renders the template on startup and whenever the lease renews.
# ---------------------------------------------------------------------------

resource "kubernetes_config_map" "agent_demo_config" {
  metadata {
    name      = "agent-demo-config"
    namespace = "sg-app"
    labels    = local.labels
  }
  data = {
    "agent.hcl"         = <<-HCL
      auto_auth {
        method "kubernetes" {
          namespace = "shift-gear"
          mount_path = "auth/kubernetes"
          config = {
            role = "sg-agent-demo"
          }
        }
        sink "file" {
          config = {
            path = "/vault/secrets/.token"
          }
        }
      }

      vault {
        address = "https://vault-active.sg-vault.svc:8200"
        ca_cert = "/vault/userconfig/sg-ca/ca.pem"
        namespace = "shift-gear"
      }

      template {
        source      = "/vault/templates/demo-secret.ctmpl"
        destination = "/vault/secrets/demo-secret"
        perms       = "0440"
      }
    HCL
    "demo-secret.ctmpl" = <<-TMPL
      {{ "{{" }}- with secret "kv/data/shift-gear/agent/demo-secret" {{ "}}" }}
      {{ "{{" }} range $key, $_ := .Data.data {{ "}}" }}{{ "{{" }} $key {{ "}}" }}={{ "{{" }} index $.Data.data $key {{ "}}" }}
      {{ "{{" }}- end {{ "}}" }}
      {{ "{{" }}- end {{ "}}" }}
    TMPL
  }
}

resource "kubernetes_deployment" "agent_demo" {
  metadata {
    name      = "agent-demo"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "agent-demo"
      }
    }
    template {
      metadata {
        labels = merge(local.labels, {
          "app.kubernetes.io/name" = "agent-demo"
        })
        annotations = {
          "openshift.io/required-scc" = "restricted-v2"
        }
      }
      spec {
        service_account_name = "sg-agent-demo"
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        # Vault Agent init container: renders the secret before the app starts
        init_container {
          name  = "vault-agent-init"
          image = "docker.io/hashicorp/vault-enterprise:2.1.0-ent@sha256:12c3ac1469d11da17747927128ed11bce825a012d3ce13b066d0442d0105df0a"
          args  = ["agent", "-config=/vault/config/agent.hcl", "-exit-after-auth"]
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { memory = "128Mi" }
          }
          volume_mount {
            name       = "agent-config"
            mount_path = "/vault/config"
            read_only  = true
          }
          volume_mount {
            name       = "vault-templates"
            mount_path = "/vault/templates"
            read_only  = true
          }
          volume_mount {
            name       = "vault-secrets"
            mount_path = "/vault/secrets"
          }
          volume_mount {
            name       = "sg-ca"
            mount_path = "/vault/userconfig/sg-ca"
            read_only  = true
          }
        }
        # Vault Agent sidecar: keeps the token and secret fresh
        container {
          name  = "vault-agent"
          image = "docker.io/hashicorp/vault-enterprise:2.1.0-ent@sha256:12c3ac1469d11da17747927128ed11bce825a012d3ce13b066d0442d0105df0a"
          args  = ["agent", "-config=/vault/config/agent.hcl"]
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = { cpu = "20m", memory = "64Mi" }
            limits   = { memory = "128Mi" }
          }
          volume_mount {
            name       = "agent-config"
            mount_path = "/vault/config"
            read_only  = true
          }
          volume_mount {
            name       = "vault-templates"
            mount_path = "/vault/templates"
            read_only  = true
          }
          volume_mount {
            name       = "vault-secrets"
            mount_path = "/vault/secrets"
          }
          volume_mount {
            name       = "sg-ca"
            mount_path = "/vault/userconfig/sg-ca"
            read_only  = true
          }
        }
        # App container — reads /vault/secrets/demo-secret, never Vault directly
        container {
          name    = "app"
          image   = "registry.access.redhat.com/ubi9/ubi-micro:latest"
          command = ["/bin/sh", "-c"]
          args = [<<-CMD
            echo "agent-demo: secret keys: $$(cat /vault/secrets/demo-secret 2>/dev/null | cut -d= -f1 | tr '\n' ' ')"
            sleep 86400
          CMD
          ]
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = { cpu = "10m", memory = "16Mi" }
            limits   = { memory = "32Mi" }
          }
          volume_mount {
            name       = "vault-secrets"
            mount_path = "/vault/secrets"
            read_only  = true
          }
          # No VAULT_* env vars — the whole point of the agent sidecar pattern
        }
        volume {
          name = "agent-config"
          config_map {
            name = kubernetes_config_map.agent_demo_config.metadata[0].name
          }
        }
        volume {
          name = "vault-templates"
          config_map {
            name = kubernetes_config_map.agent_demo_config.metadata[0].name
          }
        }
        volume {
          name = "vault-secrets"
          empty_dir {}
        }
        volume {
          name = "sg-ca"
          config_map {
            name = "sg-ca"
          }
        }
      }
    }
  }
  wait_for_rollout = false
  timeouts {
    create = "5m"
    update = "5m"
  }
}

# ---------------------------------------------------------------------------
# Route keycloak.<apps_domain> → keycloak:8443 (reencrypt). The router verifies
# Keycloak's certificate with the project CA (public, from the sg-ca ConfigMap
# ansible prepare writes); without destinationCACertificate every request
# answers 503. Here and not in foundation because the CA exists only after
# prepare. The `iss` claim equals this URL.
# ---------------------------------------------------------------------------
data "kubernetes_config_map_v1" "sg_ca_identity" {
  metadata {
    name      = "sg-ca"
    namespace = "sg-identity"
  }
}

resource "kubernetes_manifest" "route_keycloak" {
  manifest = {
    apiVersion = "route.openshift.io/v1"
    kind       = "Route"
    metadata = {
      name      = "keycloak"
      namespace = "sg-identity"
      labels    = local.labels
    }
    spec = {
      host = "keycloak.${local.apps_domain}"
      port = { targetPort = "https" }
      tls = {
        termination                   = "reencrypt"
        insecureEdgeTerminationPolicy = "Redirect"
        destinationCACertificate      = data.kubernetes_config_map_v1.sg_ca_identity.data["ca.pem"]
      }
      to = {
        kind   = "Service"
        name   = "keycloak"
        weight = 100
      }
    }
  }
}

# ---------------------------------------------------------------------------
# The console (sg-app): Nuxt 4 SPA + Nitro BFF, built in-cluster by ansible ux.
# Observe-only: it reads evidence from ConfigMap sg-evidence and calls Vault
# only for OIDC sign-in and the signed-in user's own requests. No Vault or
# Kubernetes token of its own.
# ---------------------------------------------------------------------------
resource "kubernetes_deployment" "ui" {
  metadata {
    name      = "sg-ui"
    namespace = "sg-app"
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "sg-ui" })
  }
  spec {
    replicas = 1
    selector {
      match_labels = { "app.kubernetes.io/name" = "sg-ui" }
    }
    template {
      metadata {
        labels = merge(local.labels, { "app.kubernetes.io/name" = "sg-ui" })
        annotations = {
          "openshift.io/required-scc" = "restricted-v2"
        }
      }
      spec {
        automount_service_account_token = false
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name = "ui"
          # Built by ansible ux; pulled again on every pod start.
          image             = "image-registry.openshift-image-registry.svc:5000/sg-app/shift-gear-ui:latest"
          image_pull_policy = "Always"
          port {
            name           = "http"
            container_port = 3000
          }
          env {
            name  = "NUXT_VAULT_ADDR"
            value = "https://vault-active.sg-vault.svc:8200"
          }
          env {
            name  = "NUXT_VAULT_NAMESPACE"
            value = "shift-gear"
          }
          env {
            name  = "NUXT_VAULT_CA_FILE"
            value = "/ca/ca.pem"
          }
          env {
            name  = "NUXT_OIDC_REDIRECT_URI"
            value = "https://shiftgear.${local.apps_domain}/auth/callback"
          }
          env {
            name  = "NUXT_EVIDENCE_DIR"
            value = "/evidence"
          }
          env {
            name  = "NUXT_AUDIT_API_BASE"
            value = "http://${kubernetes_service.audit_collector.metadata[0].name}.sg-app.svc:8080"
          }
          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            period_seconds = 10
          }
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { memory = "512Mi" }
          }
          volume_mount {
            name       = "ca"
            mount_path = "/ca"
            read_only  = true
          }
          volume_mount {
            name       = "evidence"
            mount_path = "/evidence"
            read_only  = true
          }
        }
        volume {
          name = "ca"
          config_map {
            name = "sg-ca"
          }
        }
        # Synced by ansible ux after the secret scan; optional until the first sync.
        volume {
          name = "evidence"
          config_map {
            name     = "sg-evidence"
            optional = true
          }
        }
      }
    }
  }
  # The pod cannot run before ansible ux has built the image.
  wait_for_rollout = false
}

resource "kubernetes_service" "ui" {
  metadata {
    name      = "sg-ui"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    selector = { "app.kubernetes.io/name" = "sg-ui" }
    port {
      name        = "http"
      port        = 3000
      target_port = 3000
    }
  }
}

# shiftgear.<apps_domain>: TLS at the router (edge), HTTP→HTTPS redirect; the
# BFF sets Secure cookies. The pod serves plain HTTP inside the cluster only.
resource "kubernetes_manifest" "route_ui" {
  manifest = {
    apiVersion = "route.openshift.io/v1"
    kind       = "Route"
    metadata = {
      name      = "shiftgear"
      namespace = "sg-app"
      labels    = local.labels
    }
    spec = {
      host = "shiftgear.${local.apps_domain}"
      port = { targetPort = "http" }
      tls = {
        termination                   = "edge"
        insecureEdgeTerminationPolicy = "Redirect"
      }
      to = {
        kind   = "Service"
        name   = "sg-ui"
        weight = 100
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Audit collector (sg-audit, sg-app): the far end of Vault's socket audit
# device, and the source of the console's Audit page. A dependency-free Node
# program (collector/server.mjs) mounted from a ConfigMap onto a pinned UBI
# Node.js image: no image build, so it stays out of the Ansible build path.
# The platform root enables the socket device; Vault refuses to enable one it
# cannot reach, so this Deployment waits for its rollout.
# ---------------------------------------------------------------------------
locals {
  audit_collector_source = file("${path.module}/../../collector/server.mjs")
}

resource "kubernetes_config_map" "audit_collector" {
  metadata {
    name      = "sg-audit-collector"
    namespace = "sg-app"
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "sg-audit" })
  }
  data = {
    "server.mjs" = local.audit_collector_source
  }
}

resource "kubernetes_deployment" "audit_collector" {
  metadata {
    name      = "sg-audit"
    namespace = "sg-app"
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "sg-audit" })
  }
  spec {
    replicas = 1
    selector {
      match_labels = { "app.kubernetes.io/name" = "sg-audit" }
    }
    template {
      metadata {
        labels = merge(local.labels, { "app.kubernetes.io/name" = "sg-audit" })
        annotations = {
          "openshift.io/required-scc" = "restricted-v2"
          # A new collector program rolls the pod.
          "shift-gear/collector-sha256" = sha256(local.audit_collector_source)
        }
      }
      spec {
        automount_service_account_token = false
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name = "collector"
          # registry.access.redhat.com/ubi9/nodejs-22-minimal, multi-arch
          # manifest list (arm64 + amd64), pinned 2026-10-09.
          image   = "registry.access.redhat.com/ubi9/nodejs-22-minimal@sha256:03b7dd64cafaaca5019c4cc1c36e05140b1650dab6cd5c4ab1fde9d88c0537ca"
          command = ["node", "/opt/collector/server.mjs"]
          port {
            name           = "ingest"
            container_port = 9090
          }
          port {
            name           = "http"
            container_port = 8080
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            period_seconds = 5
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            period_seconds    = 20
            failure_threshold = 3
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { memory = "128Mi" }
          }
          volume_mount {
            name       = "collector"
            mount_path = "/opt/collector"
            read_only  = true
          }
        }
        volume {
          name = "collector"
          config_map {
            name = kubernetes_config_map.audit_collector.metadata[0].name
          }
        }
      }
    }
  }
  wait_for_rollout = true
}

resource "kubernetes_service" "audit_collector" {
  metadata {
    name      = "sg-audit"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    selector = { "app.kubernetes.io/name" = "sg-audit" }
    port {
      name        = "ingest"
      port        = 9090
      target_port = 9090
    }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}

# Only Vault may write audit lines (9090), and only the console may read them
# (8080). Selects the collector pods only; the console's own ingress is
# untouched.
resource "kubernetes_network_policy" "audit_collector" {
  metadata {
    name      = "sg-audit-ingress"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = { "app.kubernetes.io/name" = "sg-audit" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "sg-vault" }
        }
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "vault" }
        }
      }
      ports {
        port     = 9090
        protocol = "TCP"
      }
    }
    ingress {
      from {
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "sg-ui" }
        }
      }
      ports {
        port     = 8080
        protocol = "TCP"
      }
    }
  }
}
