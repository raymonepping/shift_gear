# terraform/foundation/main.tf
# Foundation layer: namespaces, RBAC, ServiceAccounts, NetworkPolicies,
# Routes, VSO Subscription, ImageStreams + BuildConfigs.
# Reads the substrate contract from terraform/infra via remote_state.
#
# This module does NOT know CRC. It consumes only local.cluster.

terraform {
  backend "local" {
    # Path is relative to terraform/foundation/ (the Terraform working directory)
    path = "../../.secrets/terraform/foundation/terraform.tfstate"
  }
}

data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    # Path is relative to terraform/foundation/ (the Terraform working directory)
    path = "../../.secrets/terraform/infra/terraform.tfstate"
  }
}

locals {
  cluster     = data.terraform_remote_state.infra.outputs.cluster
  apps_domain = local.cluster.apps_domain
  labels = {
    "app.kubernetes.io/part-of"    = "shift-gear"
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

provider "kubernetes" {
  # kubeconfig_path in contract is relative to project root; foundation runs from terraform/foundation/
  config_path = abspath("${path.root}/../../${local.cluster.kubeconfig_path}")
}

provider "helm" {
  kubernetes {
    config_path = abspath("${path.root}/../../${local.cluster.kubeconfig_path}")
  }
}

# ---------------------------------------------------------------------------
# Namespaces
# ---------------------------------------------------------------------------
resource "kubernetes_namespace" "sg_vault_seal" {
  metadata {
    name   = "sg-vault-seal"
    labels = local.labels
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_namespace" "sg_vault" {
  metadata {
    name   = "sg-vault"
    labels = local.labels
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_namespace" "sg_identity" {
  metadata {
    name   = "sg-identity"
    labels = local.labels
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_namespace" "sg_workloads" {
  metadata {
    name   = "sg-workloads"
    labels = local.labels
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_namespace" "sg_app" {
  metadata {
    name   = "sg-app"
    labels = local.labels
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

# ---------------------------------------------------------------------------
# ServiceAccounts (seal-agent, seal-rotator) in sg-vault-seal
# ---------------------------------------------------------------------------
resource "kubernetes_service_account" "seal_agent" {
  metadata {
    name      = "seal-agent"
    namespace = kubernetes_namespace.sg_vault_seal.metadata[0].name
    labels    = local.labels
  }

  # OpenShift's controller adds a dockercfg pull Secret, a secret reference
  # and an annotation to every ServiceAccount; they are not Terraform's.
  lifecycle {
    ignore_changes = [
      image_pull_secret,
      secret,
      metadata[0].annotations["openshift.io/internal-registry-pull-secret-ref"],
    ]
  }
}

resource "kubernetes_service_account" "seal_rotator" {
  metadata {
    name      = "seal-rotator"
    namespace = kubernetes_namespace.sg_vault_seal.metadata[0].name
    labels    = local.labels
  }

  # OpenShift's controller adds a dockercfg pull Secret, a secret reference
  # and an annotation to every ServiceAccount; they are not Terraform's.
  lifecycle {
    ignore_changes = [
      image_pull_secret,
      secret,
      metadata[0].annotations["openshift.io/internal-registry-pull-secret-ref"],
    ]
  }
}

# ---------------------------------------------------------------------------
# RBAC: seal-rotator may only get/patch Secret seal-agent-approle
# ---------------------------------------------------------------------------
resource "kubernetes_role" "seal_rotator" {
  metadata {
    name      = "seal-rotator"
    namespace = kubernetes_namespace.sg_vault_seal.metadata[0].name
    labels    = local.labels
  }
  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = ["seal-agent-approle"]
    verbs          = ["get", "patch"]
  }
}

resource "kubernetes_role_binding" "seal_rotator" {
  metadata {
    name      = "seal-rotator"
    namespace = kubernetes_namespace.sg_vault_seal.metadata[0].name
    labels    = local.labels
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.seal_rotator.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.seal_rotator.metadata[0].name
    namespace = kubernetes_namespace.sg_vault_seal.metadata[0].name
  }
}

# ---------------------------------------------------------------------------
# NetworkPolicies
# ---------------------------------------------------------------------------

# seal-agent accepts :8200 only from Vault pods in sg-vault
resource "kubernetes_network_policy" "seal_agent_ingress" {
  metadata {
    name      = "seal-agent-ingress"
    namespace = kubernetes_namespace.sg_vault_seal.metadata[0].name
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "seal-agent"
      }
    }
    policy_types = ["Ingress"]
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
        port     = 8200
        protocol = "TCP"
      }
    }
  }
}

# vault-seal accepts :8200 from seal-agent, seal-rotator pods, and the router
resource "kubernetes_network_policy" "vault_seal_ingress" {
  metadata {
    name      = "vault-seal-ingress"
    namespace = kubernetes_namespace.sg_vault_seal.metadata[0].name
    labels    = local.labels
  }
  spec {
    # The Vault chart labels every server pod app.kubernetes.io/name=vault;
    # the release name tells the seal Vault apart. Selecting name=vault-seal
    # matched no pod and left the seal Vault open.
    pod_selector {
      match_labels = {
        "app.kubernetes.io/instance" = "vault-seal"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "seal-agent"
          }
        }
      }
      ports {
        port     = 8200
        protocol = "TCP"
      }
    }
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "seal-rotator"
          }
        }
      }
      ports {
        port     = 8200
        protocol = "TCP"
      }
    }
    # OpenShift router (passthrough Route)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "policy-group.network.openshift.io/ingress" = ""
          }
        }
      }
      # The CRC router uses HostNetwork publishing: on OVN-Kubernetes its
      # traffic arrives from the host network, selected by this label.
      from {
        namespace_selector {
          match_labels = {
            "policy-group.network.openshift.io/host-network" = ""
          }
        }
      }
      ports {
        port     = 8200
        protocol = "TCP"
      }
    }
  }
}

# sg-vault: 8200/8201 between pods; 8200 from router, sg-workloads, sg-app, openshift-operators
resource "kubernetes_network_policy" "vault_ingress" {
  metadata {
    name      = "vault-ingress"
    namespace = kubernetes_namespace.sg_vault.metadata[0].name
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "vault"
      }
    }
    policy_types = ["Ingress"]
    # Raft peer traffic within sg-vault
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "vault"
          }
        }
      }
      ports {
        port     = 8200
        protocol = "TCP"
      }
      ports {
        port     = 8201
        protocol = "TCP"
      }
    }
    # OpenShift router
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "policy-group.network.openshift.io/ingress" = ""
          }
        }
      }
      # The CRC router uses HostNetwork publishing: on OVN-Kubernetes its
      # traffic arrives from the host network, selected by this label.
      from {
        namespace_selector {
          match_labels = {
            "policy-group.network.openshift.io/host-network" = ""
          }
        }
      }
      ports {
        port     = 8200
        protocol = "TCP"
      }
    }
    # sg-workloads, sg-app, openshift-operators (VSO)
    ingress {
      from {
        namespace_selector {
          match_expressions {
            key      = "kubernetes.io/metadata.name"
            operator = "In"
            values   = ["sg-workloads", "sg-app", "openshift-operators"]
          }
        }
      }
      ports {
        port     = 8200
        protocol = "TCP"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# OpenShift Routes
# ---------------------------------------------------------------------------

# vault.<apps_domain> → vault-active (passthrough TLS)
resource "kubernetes_manifest" "route_vault" {
  manifest = {
    apiVersion = "route.openshift.io/v1"
    kind       = "Route"
    metadata = {
      name      = "vault"
      namespace = kubernetes_namespace.sg_vault.metadata[0].name
      labels    = local.labels
    }
    spec = {
      host = "vault.${local.apps_domain}"
      port = { targetPort = "https" }
      tls  = { termination = "passthrough" }
      to = {
        kind   = "Service"
        name   = "vault-active"
        weight = 100
      }
    }
  }
}

# vault-seal.<apps_domain> → vault-seal (passthrough TLS)
resource "kubernetes_manifest" "route_vault_seal" {
  manifest = {
    apiVersion = "route.openshift.io/v1"
    kind       = "Route"
    metadata = {
      name      = "vault-seal"
      namespace = kubernetes_namespace.sg_vault_seal.metadata[0].name
      labels    = local.labels
    }
    spec = {
      host = "vault-seal.${local.apps_domain}"
      port = { targetPort = "https" }
      tls  = { termination = "passthrough" }
      to = {
        kind   = "Service"
        name   = "vault-seal"
        weight = 100
      }
    }
  }
}

# Route keycloak.<apps_domain> lives in terraform/workloads: as a reencrypt
# Route it needs the project CA, which exists only after ansible prepare.

# ---------------------------------------------------------------------------
# OpenLDAP image: ImageStream + BuildConfig
# Built in-cluster from deploy/identity/openldap/ so no external registry
# pull is needed at runtime and the image is owned by this project.
# The ImageStream tag "latest" is updated after every successful build.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "openldap_imagestream" {
  manifest = {
    apiVersion = "image.openshift.io/v1"
    kind       = "ImageStream"
    metadata = {
      name      = "openldap"
      namespace = kubernetes_namespace.sg_identity.metadata[0].name
      labels    = local.labels
    }
    spec = {
      lookupPolicy = { local = true }
    }
  }
}

resource "kubernetes_manifest" "openldap_buildconfig" {
  manifest = {
    apiVersion = "build.openshift.io/v1"
    kind       = "BuildConfig"
    metadata = {
      name      = "openldap"
      namespace = kubernetes_namespace.sg_identity.metadata[0].name
      labels    = local.labels
    }
    spec = {
      source = {
        type   = "Binary"
        binary = {}
      }
      strategy = {
        type = "Docker"
        # Alpine:3.22 multi-arch; arm64 is selected automatically. No fields set:
        # OpenShift drops defaults such as noCache=false on save, and
        # kubernetes_manifest then reports an inconsistent result.
        dockerStrategy = {}
      }
      output = {
        to = {
          kind = "ImageStreamTag"
          name = "openldap:latest"
        }
      }
      successfulBuildsHistoryLimit = 3
      failedBuildsHistoryLimit     = 3
      runPolicy                    = "Serial"
    }
  }
}

# ---------------------------------------------------------------------------
# Vault Secrets Operator — certified OperatorHub subscription
# Installed into openshift-operators (AllNamespaces)
# ---------------------------------------------------------------------------
resource "kubernetes_manifest" "vso_subscription" {
  manifest = {
    apiVersion = "operators.coreos.com/v1alpha1"
    kind       = "Subscription"
    metadata = {
      name      = "vault-secrets-operator"
      namespace = "openshift-operators"
      labels    = local.labels
    }
    spec = {
      channel             = "stable"
      name                = "vault-secrets-operator"
      source              = "certified-operators"
      sourceNamespace     = "openshift-marketplace"
      installPlanApproval = "Automatic"
    }
  }
}

# ---------------------------------------------------------------------------
# VSO ServiceAccount + vault-token-reviewer
# vso-workloads SA: used by the VaultAuth resource in sg-workloads.
# vault-token-reviewer SA: used by Vault's kubernetes auth to review tokens.
#   - ClusterRoleBinding to system:auth-delegator (required for TokenReview)
#   - Long-lived Secret of type kubernetes.io/service-account-token so Vault
#     can use it as the token_reviewer_jwt without projecting a volume.
# ---------------------------------------------------------------------------

resource "kubernetes_service_account" "vso_workloads" {
  metadata {
    name      = "vso-workloads"
    namespace = kubernetes_namespace.sg_workloads.metadata[0].name
    labels    = local.labels
  }

  # OpenShift's controller adds a dockercfg pull Secret, a secret reference
  # and an annotation to every ServiceAccount; they are not Terraform's.
  lifecycle {
    ignore_changes = [
      image_pull_secret,
      secret,
      metadata[0].annotations["openshift.io/internal-registry-pull-secret-ref"],
    ]
  }
}

resource "kubernetes_service_account" "vault_token_reviewer" {
  metadata {
    name      = "vault-token-reviewer"
    namespace = kubernetes_namespace.sg_vault.metadata[0].name
    labels    = local.labels
  }

  # OpenShift's controller adds a dockercfg pull Secret, a secret reference
  # and an annotation to every ServiceAccount; they are not Terraform's.
  lifecycle {
    ignore_changes = [
      image_pull_secret,
      secret,
      metadata[0].annotations["openshift.io/internal-registry-pull-secret-ref"],
    ]
  }
}

# system:auth-delegator allows the SA to call the TokenReview API.
resource "kubernetes_cluster_role_binding" "vault_token_reviewer" {
  metadata {
    name   = "vault-token-reviewer"
    labels = local.labels
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_token_reviewer.metadata[0].name
    namespace = kubernetes_namespace.sg_vault.metadata[0].name
  }
}

# Long-lived token: kubernetes.io/service-account-token is stable across
# rotations and does not require a pod to project it. Vault stores this
# value once during configure (ansible configure) and never needs it again.
resource "kubernetes_secret" "vault_token_reviewer" {
  metadata {
    name      = "vault-token-reviewer-token"
    namespace = kubernetes_namespace.sg_vault.metadata[0].name
    labels    = local.labels
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.vault_token_reviewer.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
  # The token is auto-populated by the API server; never set in state.
  wait_for_service_account_token = true
}

# ServiceAccounts for sg-app workloads
resource "kubernetes_service_account" "sg_api" {
  metadata {
    name      = "sg-api"
    namespace = kubernetes_namespace.sg_app.metadata[0].name
    labels    = local.labels
  }

  # OpenShift's controller adds a dockercfg pull Secret, a secret reference
  # and an annotation to every ServiceAccount; they are not Terraform's.
  lifecycle {
    ignore_changes = [
      image_pull_secret,
      secret,
      metadata[0].annotations["openshift.io/internal-registry-pull-secret-ref"],
    ]
  }
}

resource "kubernetes_service_account" "sg_agent_demo" {
  metadata {
    name      = "sg-agent-demo"
    namespace = kubernetes_namespace.sg_app.metadata[0].name
    labels    = local.labels
  }

  # OpenShift's controller adds a dockercfg pull Secret, a secret reference
  # and an annotation to every ServiceAccount; they are not Terraform's.
  lifecycle {
    ignore_changes = [
      image_pull_secret,
      secret,
      metadata[0].annotations["openshift.io/internal-registry-pull-secret-ref"],
    ]
  }
}

# ---------------------------------------------------------------------------
# Console image: ImageStream + binary Docker BuildConfig (sg-app). Built
# in-cluster by ansible ux (oc start-build --from-archive) from ui/; no
# local container engine, no registry exposed outside the cluster.
# ---------------------------------------------------------------------------
resource "kubernetes_manifest" "ui_imagestream" {
  manifest = {
    apiVersion = "image.openshift.io/v1"
    kind       = "ImageStream"
    metadata = {
      name      = "shift-gear-ui"
      namespace = kubernetes_namespace.sg_app.metadata[0].name
      labels    = local.labels
    }
    spec = {
      lookupPolicy = { local = true }
    }
  }
}

resource "kubernetes_manifest" "ui_buildconfig" {
  manifest = {
    apiVersion = "build.openshift.io/v1"
    kind       = "BuildConfig"
    metadata = {
      name      = "shift-gear-ui"
      namespace = kubernetes_namespace.sg_app.metadata[0].name
      labels    = local.labels
    }
    spec = {
      source = { type = "Binary" }
      strategy = {
        type = "Docker"
        # No fields set: OpenShift drops defaults on save (see openldap).
        dockerStrategy = {}
      }
      output = {
        to = {
          kind = "ImageStreamTag"
          name = "shift-gear-ui:latest"
        }
      }
    }
  }
}
