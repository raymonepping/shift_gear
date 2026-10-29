# The Secure Door pod: four containers, one job each.
#   vault-agent  the only Vault client: Kubernetes auth (projected token mounted
#                here only), no sink, no listener; renders one atomic JSON
#                snapshot of the watched secret into a memory-backed volume.
#   vault-probe  unauthenticated `vault status` every 5 s -> /health/vault.json
#                (reachability only). Holds no token.
#   consumer     Python stdlib: polls the snapshot, hot-reloads, runs the
#                fictional Secure Door, writes non-secret /status/state.json.
#   board        Node, dependency-free: serves the board from /status only.
# restricted-v2 runs all four as the same UID, so isolation is by *mounts*
# (each volume read-only where it is consumed), not by file permissions.

locals {
  apps_domain = data.terraform_remote_state.infra.outputs.cluster.apps_domain
  labels = {
    "app.kubernetes.io/part-of"    = "shift-gear"
    "app.kubernetes.io/managed-by" = "terraform"
    "shift-gear/addon"             = "rotation-consumer"
  }
  app_labels = merge(local.labels, { "app.kubernetes.io/name" = "secure-door" })
  vault_addr = "https://vault-active.sg-vault.svc:8200"
  ca_path    = "/vault/userconfig/sg-ca/ca.pem"
  secret_id  = trimprefix(var.secret_path, "shift-gear/rotation/")

  code_files = { for f in fileset("${path.module}/../consumer/secure_door", "*.py") :
  f => file("${path.module}/../consumer/secure_door/${f}") }
  board_static = { for f in fileset("${path.module}/../board/static", "*") :
  f => file("${path.module}/../board/static/${f}") }

  agent_hcl = <<-HCL
    # Secure Door Vault Agent: renders the watched KV v2 secret as one atomic
    # JSON snapshot. No sink (the token never touches disk), no listener, no
    # api_proxy: nothing else in the pod can use this identity.
    pid_file             = "/tmp/agent.pid"
    log_file             = "/agent-log/agent.log"
    log_level            = "trace"
    log_rotate_bytes     = 1048576
    log_rotate_max_files = 1

    auto_auth {
      method "kubernetes" {
        namespace  = "${var.vault_namespace}"
        mount_path = "auth/kubernetes"
        config = {
          role       = "sg-rotation-consumer"
          token_path = "/var/run/secrets/vault-token/token"
        }
      }
    }

    vault {
      address   = "${local.vault_addr}"
      ca_cert   = "${local.ca_path}"
      namespace = "${var.vault_namespace}"
    }

    template_config {
      static_secret_render_interval = "${var.render_interval}"
      exit_on_retry_failure         = false
    }

    template {
      contents             = "{{ with secret \"kv/data/${var.secret_path}\" }}{{ .Data | toJSON }}{{ end }}"
      destination          = "/vault/render/secret.json"
      perms                = "0440"
      error_on_missing_key = true
    }
  HCL

  probe_sh = <<-SH
    #!/bin/sh
    # Vault connectivity, explicitly: unauthenticated `vault status` (rc 0 =
    # unsealed, 2 = sealed, anything else = unreachable). Reachability only.
    set -u
    while :; do
      # 3 s client timeout: a dropped connection must not hold the probe for the
      # CLI's default timeout (measured 34.6 s in c04 before this setting).
      # (`vault status` has no -client-timeout flag; the env var is honoured.)
      out="$(VAULT_CLIENT_TIMEOUT=3s vault status -address=${local.vault_addr} -ca-cert=${local.ca_path} -format=json 2>/dev/null)"
      rc=$?
      reachable=false; sealed=null
      if [ "$rc" -eq 0 ]; then reachable=true; sealed=false; fi
      if [ "$rc" -eq 2 ]; then reachable=true; sealed=true; fi
      printf '{"reachable":%s,"sealed":%s,"rc":%d,"at":"%s"}\n' "$reachable" "$sealed" "$rc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /health/.vault.json.tmp
      mv /health/.vault.json.tmp /health/vault.json
      sleep 5
    done
  SH

  checksum = sha256(join("", concat(
    [for k in sort(keys(local.code_files)) : local.code_files[k]],
    [for k in sort(keys(local.board_static)) : local.board_static[k]],
    [file("${path.module}/../board/server.mjs"), local.agent_hcl, local.probe_sh],
  )))
}

resource "kubernetes_namespace" "consumer" {
  metadata {
    name   = var.namespace
    labels = local.labels
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_service_account" "door" {
  metadata {
    name      = "secure-door"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  automount_service_account_token = false
  lifecycle {
    ignore_changes = [image_pull_secret, secret, metadata[0].annotations["openshift.io/internal-registry-pull-secret-ref"]]
  }
}

data "kubernetes_config_map" "core_ca" {
  metadata {
    name      = "sg-ca"
    namespace = "sg-app"
  }
}

resource "kubernetes_config_map" "ca" {
  metadata {
    name      = "sg-ca"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  data = { "ca.pem" = data.kubernetes_config_map.core_ca.data["ca.pem"] }
}

resource "kubernetes_config_map" "agent" {
  metadata {
    name      = "secure-door-agent"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  data = { "agent.hcl" = local.agent_hcl, "probe.sh" = local.probe_sh }
}

resource "kubernetes_config_map" "code" {
  metadata {
    name      = "secure-door-code"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  data = local.code_files
}

resource "kubernetes_config_map" "board" {
  metadata {
    name      = "secure-door-board"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  data = merge(local.board_static, { "server.mjs" = file("${path.module}/../board/server.mjs") })
}

# Self-hosted fonts (the console's own woff2 files), as binary data.
resource "kubernetes_config_map" "fonts" {
  metadata {
    name      = "secure-door-fonts"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  binary_data = {
    "hanken-grotesk.woff2" = filebase64("${path.module}/../../../../ui/node_modules/@fontsource-variable/hanken-grotesk/files/hanken-grotesk-latin-wght-normal.woff2")
    "jetbrains-mono.woff2" = filebase64("${path.module}/../../../../ui/node_modules/@fontsource-variable/jetbrains-mono/files/jetbrains-mono-latin-wght-normal.woff2")
  }
}

# The last seen KV version (non-secret) survives a stopped consumer, so a
# restart can report "v54 -> v58; missed 3". Mounted into `consumer` only.
resource "kubernetes_persistent_volume_claim" "state" {
  metadata {
    name      = "secure-door-state"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "64Mi" }
    }
  }
  wait_until_bound = false
}

resource "kubernetes_deployment" "door" {
  metadata {
    name      = "secure-door"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.app_labels
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { "app.kubernetes.io/name" = "secure-door" }
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
        service_account_name            = kubernetes_service_account.door.metadata[0].name
        automount_service_account_token = false
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "vault-agent"
          image = var.vault_image
          args  = ["agent", "-config=/vault/config/agent.hcl"]
          env {
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
            requests = { cpu = "10m", memory = "48Mi" }
            limits   = { memory = "96Mi" }
          }
          volume_mount {
            name       = "vault-token"
            mount_path = "/var/run/secrets/vault-token"
            read_only  = true
          }
          volume_mount {
            name       = "agent-config"
            mount_path = "/vault/config"
            read_only  = true
          }
          volume_mount {
            name       = "ca"
            mount_path = "/vault/userconfig/sg-ca"
            read_only  = true
          }
          volume_mount {
            name       = "render"
            mount_path = "/vault/render"
          }
          volume_mount {
            name       = "agent-log"
            mount_path = "/agent-log"
          }
          volume_mount {
            name       = "tmp-agent"
            mount_path = "/tmp"
          }
        }

        container {
          name    = "vault-probe"
          image   = var.vault_image
          command = ["/bin/sh", "/vault/config/probe.sh"]
          env {
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
            requests = { cpu = "5m", memory = "24Mi" }
            limits   = { memory = "64Mi" }
          }
          volume_mount {
            name       = "agent-config"
            mount_path = "/vault/config"
            read_only  = true
          }
          volume_mount {
            name       = "ca"
            mount_path = "/vault/userconfig/sg-ca"
            read_only  = true
          }
          volume_mount {
            name       = "health"
            mount_path = "/health"
          }
          volume_mount {
            name       = "tmp-probe"
            mount_path = "/tmp"
          }
        }

        container {
          name    = "consumer"
          image   = var.python_image
          command = ["python3", "-m", "secure_door"]
          env {
            name  = "PYTHONPATH"
            value = "/opt/consumer"
          }
          env {
            name  = "PYTHONDONTWRITEBYTECODE"
            value = "1"
          }
          env {
            name  = "CONSUMER_SECRET"
            value = local.secret_id
          }
          env {
            name  = "CONSUMER_POLL_S"
            value = tostring(var.poll_seconds)
          }
          env {
            name  = "CONSUMER_VALIDATE_S"
            value = tostring(var.validate_seconds)
          }
          env {
            name  = "CONSUMER_STALE_AFTER_S"
            value = tostring(var.stale_after_seconds)
          }
          env {
            name  = "CONSUMER_RENDER_INTERVAL_S"
            value = trimsuffix(var.render_interval, "s")
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
            limits   = { memory = "64Mi" }
          }
          volume_mount {
            name       = "code"
            mount_path = "/opt/consumer/secure_door"
            read_only  = true
          }
          volume_mount {
            name       = "render"
            mount_path = "/vault/render"
            read_only  = true
          }
          volume_mount {
            name       = "agent-log"
            mount_path = "/agent-log"
            read_only  = true
          }
          volume_mount {
            name       = "health"
            mount_path = "/health"
            read_only  = true
          }
          volume_mount {
            name       = "status"
            mount_path = "/status"
          }
          volume_mount {
            name       = "state"
            mount_path = "/state"
          }
          volume_mount {
            name       = "tmp-consumer"
            mount_path = "/tmp"
          }
          # No Vault token, no token path, no VAULT_* and no Vault address here.
        }

        container {
          name    = "board"
          image   = var.node_image
          command = ["node", "/opt/board/server.mjs"]
          env {
            name  = "BOARD_STATIC_DIR"
            value = "/opt/board"
          }
          env {
            name  = "BOARD_FONT_DIR"
            value = "/opt/board-fonts"
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
            initial_delay_seconds = 15
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
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { memory = "96Mi" }
          }
          volume_mount {
            name       = "board"
            mount_path = "/opt/board"
            read_only  = true
          }
          volume_mount {
            name       = "fonts"
            mount_path = "/opt/board-fonts"
            read_only  = true
          }
          volume_mount {
            name       = "status"
            mount_path = "/status"
            read_only  = true
          }
          volume_mount {
            name       = "tmp-board"
            mount_path = "/tmp"
          }
        }

        # Projected ServiceAccount token, audience vault — mounted into vault-agent only.
        volume {
          name = "vault-token"
          projected {
            sources {
              service_account_token {
                audience           = "vault"
                expiration_seconds = 600
                path               = "token"
              }
            }
          }
        }
        volume {
          name = "agent-config"
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
        volume {
          name = "code"
          config_map {
            name = kubernetes_config_map.code.metadata[0].name
          }
        }
        volume {
          name = "board"
          config_map {
            name = kubernetes_config_map.board.metadata[0].name
          }
        }
        volume {
          name = "fonts"
          config_map {
            name = kubernetes_config_map.fonts.metadata[0].name
          }
        }
        volume {
          name = "state"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.state.metadata[0].name
          }
        }
        dynamic "volume" {
          for_each = toset(["render", "agent-log", "health", "status", "tmp-agent", "tmp-probe", "tmp-consumer", "tmp-board"])
          content {
            name = volume.value
            empty_dir {
              medium     = "Memory"
              size_limit = volume.value == "agent-log" ? "4Mi" : "8Mi"
            }
          }
        }
      }
    }
  }
  wait_for_rollout = false
}

resource "kubernetes_service" "board" {
  metadata {
    name      = "secure-door"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.app_labels
  }
  spec {
    selector = { "app.kubernetes.io/name" = "secure-door" }
    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }
  }
}

# secure-door.<apps_domain>: TLS at the router (edge), like the console.
resource "kubernetes_manifest" "route" {
  manifest = {
    apiVersion = "route.openshift.io/v1"
    kind       = "Route"
    metadata = {
      name      = "secure-door"
      namespace = kubernetes_namespace.consumer.metadata[0].name
      labels    = local.labels
    }
    spec = {
      host = "secure-door.${local.apps_domain}"
      port = { targetPort = "http" }
      tls = {
        termination                   = "edge"
        insecureEdgeTerminationPolicy = "Redirect"
      }
      to = {
        kind   = "Service"
        name   = kubernetes_service.board.metadata[0].name
        weight = 100
      }
    }
  }
}

# ── NetworkPolicies ──────────────────────────────────────────────────────────
resource "kubernetes_network_policy" "default_deny" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

# The board: from the OpenShift router only (the core's router selector pattern).
resource "kubernetes_network_policy" "board_from_router" {
  metadata {
    name      = "board-from-router"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = { "app.kubernetes.io/name" = "secure-door" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "policy-group.network.openshift.io/ingress" = "" }
        }
      }
      from {
        namespace_selector {
          match_labels = { "policy-group.network.openshift.io/host-network" = "" }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }
}

# Additive (core object untouched): this pod may reach Vault.
resource "kubernetes_network_policy" "vault_from_consumer" {
  metadata {
    name      = "allow-sg-rotation-consumer"
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
          match_labels = { "app.kubernetes.io/name" = "secure-door" }
        }
      }
      ports {
        port     = "8200"
        protocol = "TCP"
      }
    }
  }
}

# ── Vault: read on the one watched secret, nothing else ─────────────────────
resource "vault_policy" "consumer" {
  namespace = var.vault_namespace
  name      = "sg-rotation-consumer"
  policy    = <<-HCL
    # sg-rotation-consumer — the Secure Door's Vault Agent (prompt 01_09).
    # Read the one watched secret (value + version metadata come with it).
    path "kv/data/${var.secret_path}" {
      capabilities = ["read"]
    }
  HCL
}
