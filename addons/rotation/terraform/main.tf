# Kubernetes objects of the KV rotation add-on. One namespace, one stateless
# controller pod (controller + vault-agent + vault-events), its Service and
# NetworkPolicies — plus two *additive* NetworkPolicies in core namespaces that
# admit the controller to Vault and to the audit collector. Core objects are
# never modified; `make rotation-down` removes everything below.

locals {
  labels = {
    "app.kubernetes.io/part-of"    = "shift-gear"
    "app.kubernetes.io/managed-by" = "terraform"
    "shift-gear/addon"             = "rotation"
  }
  app_labels = merge(local.labels, { "app.kubernetes.io/name" = "rotation-controller" })

  vault_addr = "https://vault-active.sg-vault.svc:8200"
  ca_path    = "/vault/userconfig/sg-ca/ca.pem"

  code_files = { for f in fileset("${path.module}/../controller/rotation", "*.py") :
  f => file("${path.module}/../controller/rotation/${f}") }

  agent_hcl = <<-HCL
    # Vault Agent for the rotation controller: Kubernetes auth, token sink for
    # the vault-events sidecar only, and an api_proxy on loopback that injects
    # the token — the controller container never holds one.
    pid_file = "/tmp/agent.pid"

    auto_auth {
      method "kubernetes" {
        namespace  = "${var.vault_namespace}"
        mount_path = "auth/kubernetes"
        config = {
          role = "sg-rotation-controller"
        }
      }
      sink "file" {
        config = {
          path = "/agent-sink/token"
        }
      }
    }

    api_proxy {
      use_auto_auth_token = "force"
    }

    listener "tcp" {
      address     = "127.0.0.1:8100"
      tls_disable = true
    }

    vault {
      address = "${local.vault_addr}"
      ca_cert = "${local.ca_path}"
    }
  HCL

  # Re-subscribes whenever the stream ends (token renewal, Vault restart) and
  # keeps the shared file small; the controller tolerates truncation.
  events_sh = <<-SH
    #!/bin/sh
    set -u
    out=/events/stream.ndjson
    : > "$out"
    ( while :; do
        size=$(wc -c < "$out" 2>/dev/null || echo 0)
        [ "$size" -gt 1048576 ] && : > "$out"
        sleep 30
      done ) &
    while :; do
      while [ ! -s /agent-sink/token ]; do sleep 2; done
      VAULT_TOKEN="$(cat /agent-sink/token)" vault events subscribe \
        -address=${local.vault_addr} -ca-cert=${local.ca_path} \
        -namespace=${var.vault_namespace} -format=json 'kv-v2/*' >> "$out" \
        || echo "vault-events: subscription ended (rc=$?), retrying" >&2
      sleep 5
    done
  SH

  checksum = sha256(join("", concat(
    [for k in sort(keys(local.code_files)) : local.code_files[k]],
    [local.config_json, local.agent_hcl, local.events_sh, tostring(var.test_mode), tostring(var.test_pause_after_write)]
  )))
}

resource "kubernetes_namespace" "rotation" {
  metadata {
    name   = var.namespace
    labels = local.labels
  }
  # OpenShift annotates every namespace (SCC ranges); same as the core roots.
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_service_account" "controller" {
  metadata {
    name      = "rotation-controller"
    namespace = kubernetes_namespace.rotation.metadata[0].name
    labels    = local.labels
  }
  automount_service_account_token = false

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

# The project CA (public) — copied from the core's sg-ca ConfigMap.
data "kubernetes_config_map" "core_ca" {
  metadata {
    name      = "sg-ca"
    namespace = "sg-app"
  }
}

resource "kubernetes_config_map" "ca" {
  metadata {
    name      = "sg-ca"
    namespace = kubernetes_namespace.rotation.metadata[0].name
    labels    = local.labels
  }
  data = { "ca.pem" = data.kubernetes_config_map.core_ca.data["ca.pem"] }
}

resource "kubernetes_config_map" "code" {
  metadata {
    name      = "rotation-controller-code"
    namespace = kubernetes_namespace.rotation.metadata[0].name
    labels    = local.labels
  }
  data = local.code_files
}

resource "kubernetes_config_map" "config" {
  metadata {
    name      = "rotation-config"
    namespace = kubernetes_namespace.rotation.metadata[0].name
    labels    = local.labels
  }
  data = { "rotation.json" = local.config_json }

  depends_on = [terraform_data.config_contract]
}

resource "kubernetes_config_map" "agent" {
  metadata {
    name      = "rotation-agent"
    namespace = kubernetes_namespace.rotation.metadata[0].name
    labels    = local.labels
  }
  data = {
    "agent.hcl" = local.agent_hcl
    "events.sh" = local.events_sh
  }
}

resource "kubernetes_deployment" "controller" {
  metadata {
    name      = "rotation-controller"
    namespace = kubernetes_namespace.rotation.metadata[0].name
    labels    = local.app_labels
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { "app.kubernetes.io/name" = "rotation-controller" }
    }
    template {
      metadata {
        labels = local.app_labels
        annotations = {
          "openshift.io/required-scc" = "restricted-v2"
          "shift-gear/config-sha256"  = local.checksum
        }
      }
      spec {
        service_account_name = kubernetes_service_account.controller.metadata[0].name
        # The agent logs in with this pod's ServiceAccount token (Kubernetes auth).
        automount_service_account_token = true
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name    = "controller"
          image   = var.python_image
          command = ["python3", "-m", "rotation.controller"]
          env {
            name  = "PYTHONPATH"
            value = "/opt/rotation"
          }
          env {
            name  = "PYTHONDONTWRITEBYTECODE"
            value = "1"
          }
          env {
            name  = "ROTATION_CONFIG"
            value = "/config/rotation.json"
          }
          env {
            name  = "ROTATION_VAULT_ADDR"
            value = "http://127.0.0.1:8100"
          }
          env {
            name  = "ROTATION_NAMESPACE"
            value = var.vault_namespace
          }
          env {
            name  = "ROTATION_AUDIT_URL"
            value = "http://sg-audit.sg-app.svc:8080"
          }
          env {
            name  = "ROTATION_EVENTS_FILE"
            value = var.events_enabled ? "/events/stream.ndjson" : ""
          }
          env {
            name  = "ROTATION_TEST_MODE"
            value = var.test_mode ? "1" : "0"
          }
          env {
            name  = "ROTATION_TEST_PAUSE_AFTER_WRITE"
            value = var.test_mode ? tostring(var.test_pause_after_write) : "0"
          }
          env {
            name  = "ROTATION_TEST_PAUSE_SECRET"
            value = var.test_mode ? "test-slow/rt-usage" : ""
          }
          port {
            name           = "http"
            container_port = 8080
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds = 10
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            initial_delay_seconds = 30
            period_seconds        = 30
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
            requests = { cpu = "20m", memory = "48Mi" }
            limits   = { memory = "96Mi" }
          }
          volume_mount {
            name       = "code"
            mount_path = "/opt/rotation/rotation"
            read_only  = true
          }
          volume_mount {
            name       = "config"
            mount_path = "/config"
            read_only  = true
          }
          volume_mount {
            name       = "events"
            mount_path = "/events"
            read_only  = true
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
          # No agent sink and no VAULT_* variables in this container.
        }

        container {
          name  = "vault-agent"
          image = var.vault_image
          args  = ["agent", "-config=/vault/config/agent.hcl"]
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = { cpu = "10m", memory = "48Mi" }
            limits   = { memory = "96Mi" }
          }
          volume_mount {
            name       = "agent"
            mount_path = "/vault/config"
            read_only  = true
          }
          volume_mount {
            name       = "agent-sink"
            mount_path = "/agent-sink"
          }
          volume_mount {
            name       = "ca"
            mount_path = "/vault/userconfig/sg-ca"
            read_only  = true
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }

        dynamic "container" {
          for_each = var.events_enabled ? [1] : []
          content {
            name    = "vault-events"
            image   = var.vault_image
            command = ["/bin/sh", "/vault/config/events.sh"]
            env {
              # The vault CLI needs a writable HOME (lesson: uid without passwd entry).
              name  = "HOME"
              value = "/tmp"
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
              requests = { cpu = "5m", memory = "32Mi" }
              limits   = { memory = "64Mi" }
            }
            volume_mount {
              name       = "agent"
              mount_path = "/vault/config"
              read_only  = true
            }
            volume_mount {
              name       = "agent-sink"
              mount_path = "/agent-sink"
              read_only  = true
            }
            volume_mount {
              name       = "events"
              mount_path = "/events"
            }
            volume_mount {
              name       = "ca"
              mount_path = "/vault/userconfig/sg-ca"
              read_only  = true
            }
            volume_mount {
              name       = "tmp"
              mount_path = "/tmp"
            }
          }
        }

        volume {
          name = "code"
          config_map {
            name = kubernetes_config_map.code.metadata[0].name
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.config.metadata[0].name
          }
        }
        volume {
          name = "agent"
          config_map {
            name = kubernetes_config_map.agent.metadata[0].name
          }
        }
        volume {
          name = "ca"
          config_map {
            name = kubernetes_config_map.ca.metadata[0].name
          }
        }
        # The token sink: shared by vault-agent and vault-events only.
        volume {
          name = "agent-sink"
          empty_dir {
            medium = "Memory"
          }
        }
        volume {
          name = "events"
          empty_dir {
            medium     = "Memory"
            size_limit = "16Mi"
          }
        }
        volume {
          name = "tmp"
          empty_dir {
            medium = "Memory"
          }
        }
      }
    }
  }
  # The pod only becomes ready once Ansible has created the Kubernetes auth
  # role; rotation-up waits for it there.
  wait_for_rollout = false
}

resource "kubernetes_service" "controller" {
  metadata {
    name      = "rotation-controller"
    namespace = kubernetes_namespace.rotation.metadata[0].name
    labels    = local.app_labels
  }
  spec {
    selector = { "app.kubernetes.io/name" = "rotation-controller" }
    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }
  }
}

# ── NetworkPolicies ──────────────────────────────────────────────────────────

# sg-rotation: nothing gets in except the console's BFF (read-only status).
resource "kubernetes_network_policy" "default_deny" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.rotation.metadata[0].name
    labels    = local.labels
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "status_from_ui" {
  metadata {
    name      = "rotation-status-from-sg-ui"
    namespace = kubernetes_namespace.rotation.metadata[0].name
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = { "app.kubernetes.io/name" = "rotation-controller" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "sg-app" }
        }
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "sg-ui" }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }
}

# Additive (core objects untouched): the controller may reach Vault …
resource "kubernetes_network_policy" "vault_from_rotation" {
  metadata {
    name      = "allow-sg-rotation"
    namespace = "sg-vault"
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = { "app.kubernetes.io/name" = "vault" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = var.namespace }
        }
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "rotation-controller" }
        }
      }
      ports {
        port     = "8200"
        protocol = "TCP"
      }
    }
  }
}

# … and read the audit collector (usage-based rotation).
resource "kubernetes_network_policy" "audit_from_rotation" {
  metadata {
    name      = "sg-audit-allow-sg-rotation"
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
          match_labels = { "kubernetes.io/metadata.name" = var.namespace }
        }
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "rotation-controller" }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }
}
