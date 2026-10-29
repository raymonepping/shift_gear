# The Secure Door, two independent parties plus a board (prompt 01_10):
#
#   door-verifier  vault-agent + vault-probe + verifier: the trust authority.
#                  Its own ServiceAccount, Kubernetes auth role and read-only policy.
#   door-client    vault-agent + vault-probe + client: hot-reloads, knocks every second.
#                  Its own ServiceAccount, role and policy.
#   door-board     Node, dependency-free: reads both parties' non-secret /status.
#
# In each party only `vault-agent` holds a token (projected, mounted there only;
# no sink, no listener). restricted-v2 runs all containers in a pod as the same
# UID, so isolation is by mounts, and between the parties by pods and identities.

locals {
  apps_domain = data.terraform_remote_state.infra.outputs.cluster.apps_domain
  labels = {
    "app.kubernetes.io/part-of"    = "shift-gear"
    "app.kubernetes.io/managed-by" = "terraform"
    "shift-gear/addon"             = "rotation-consumer"
  }
  vault_addr = "https://vault-active.sg-vault.svc:8200"
  ca_path    = "/vault/userconfig/sg-ca/ca.pem"
  secret_id  = trimprefix(var.secret_path, "shift-gear/rotation/")

  parties = {
    verifier = { name = "door-verifier", role = "sg-rotation-door-verifier" }
    client   = { name = "door-client", role = "sg-rotation-door-client" }
  }

  code_files = { for f in fileset("${path.module}/../consumer/secure_door", "*.py") :
  f => file("${path.module}/../consumer/secure_door/${f}") }
  board_static = { for f in fileset("${path.module}/../board/static", "*") :
  f => file("${path.module}/../board/static/${f}") }

  agent_hcl = { for k, p in local.parties : k => <<-HCL
    # ${p.name} Vault Agent: renders the shared secret as one atomic JSON
    # snapshot. No sink (the token never touches disk), no listener, no api_proxy.
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
          role       = "${p.role}"
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
  }

  probe_sh = <<-SH
    #!/bin/sh
    # Vault connectivity, explicitly: unauthenticated `vault status` (rc 0 =
    # unsealed, 2 = sealed, else unreachable). Reachability only. `vault status`
    # has no -client-timeout flag; VAULT_CLIENT_TIMEOUT is honoured (3 s, so a
    # dropped connection does not hold the probe for the CLI default).
    set -u
    while :; do
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

  party_env = {
    verifier = {
      DOOR_ROLE          = "verifier"
      DOOR_GRACE_SECONDS = tostring(var.grace_seconds)
      DOOR_ENTER_PORT    = "8080"
    }
    client = {
      DOOR_ROLE         = "client"
      DOOR_VERIFIER_URL = "http://door-verifier.${var.namespace}.svc:8080/enter"
      DOOR_CLIENT_ID    = "door-client"
      DOOR_REQUEST_S    = tostring(var.request_seconds)
      DOOR_STATE_FILE   = "/state/last-version.json"
    }
  }
  common_env = {
    PYTHONPATH              = "/opt/consumer"
    PYTHONDONTWRITEBYTECODE = "1"
    DOOR_SECRET             = local.secret_id
    DOOR_POLL_S             = tostring(var.poll_seconds)
    DOOR_STALE_AFTER_S      = tostring(var.stale_after_seconds)
    DOOR_RENDER_INTERVAL_S  = trimsuffix(var.render_interval, "s")
    DOOR_STATUS_PORT        = "9090"
  }

  checksum = { for k, p in local.parties : k => sha256(join("", concat(
    [for f in sort(keys(local.code_files)) : local.code_files[f]],
    [local.agent_hcl[k], local.probe_sh, jsonencode(local.party_env[k]), jsonencode(local.common_env)],
  ))) }
  board_checksum = sha256(join("", concat(
    [for f in sort(keys(local.board_static)) : local.board_static[f]],
    [file("${path.module}/../board/server.mjs")],
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

resource "kubernetes_service_account" "party" {
  for_each = local.parties
  metadata {
    name      = each.value.name
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
  for_each = local.parties
  metadata {
    name      = "${each.value.name}-agent"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  data = { "agent.hcl" = local.agent_hcl[each.key], "probe.sh" = local.probe_sh }
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

# The client's last seen version (non-secret) survives a stopped client.
resource "kubernetes_persistent_volume_claim" "client_state" {
  metadata {
    name      = "door-client-state"
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

resource "kubernetes_deployment" "party" {
  for_each = local.parties
  metadata {
    name      = each.value.name
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = each.value.name })
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { "app.kubernetes.io/name" = each.value.name }
    }
    template {
      metadata {
        labels = merge(local.labels, { "app.kubernetes.io/name" = each.value.name, "shift-gear/door-party" = each.key })
        annotations = {
          "openshift.io/required-scc" = "restricted-v2"
          "shift-gear/config-sha256"  = local.checksum[each.key]
        }
      }
      spec {
        service_account_name            = kubernetes_service_account.party[each.key].metadata[0].name
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
          name    = each.key
          image   = var.python_image
          command = ["python3", "-m", "secure_door"]
          dynamic "env" {
            for_each = merge(local.common_env, local.party_env[each.key])
            content {
              name  = env.key
              value = env.value
            }
          }
          dynamic "port" {
            for_each = each.key == "verifier" ? { enter = 8080, status = 9090 } : { status = 9090 }
            content {
              name           = port.key
              container_port = port.value
            }
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = "status"
            }
            period_seconds = 10
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
          dynamic "volume_mount" {
            for_each = each.key == "client" ? [1] : []
            content {
              name       = "state"
              mount_path = "/state"
            }
          }
          volume_mount {
            name       = "tmp-party"
            mount_path = "/tmp"
          }
          # No Vault token, no token path, no VAULT_* and no Vault address here.
        }

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
            name = kubernetes_config_map.agent[each.key].metadata[0].name
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
        dynamic "volume" {
          for_each = each.key == "client" ? [1] : []
          content {
            name = "state"
            persistent_volume_claim {
              claim_name = kubernetes_persistent_volume_claim.client_state.metadata[0].name
            }
          }
        }
        dynamic "volume" {
          for_each = toset(["render", "agent-log", "health", "tmp-agent", "tmp-probe", "tmp-party"])
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

resource "kubernetes_deployment" "board" {
  metadata {
    name      = "door-board"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "door-board" })
  }
  spec {
    replicas = 1
    selector {
      match_labels = { "app.kubernetes.io/name" = "door-board" }
    }
    template {
      metadata {
        labels = merge(local.labels, { "app.kubernetes.io/name" = "door-board" })
        annotations = {
          "openshift.io/required-scc" = "restricted-v2"
          "shift-gear/config-sha256"  = local.board_checksum
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
          env {
            name = "BOARD_SOURCES"
            value = jsonencode({
              verifier = "http://door-verifier.${var.namespace}.svc:9090/status"
              client   = "http://door-client.${var.namespace}.svc:9090/status"
            })
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
            name       = "tmp"
            mount_path = "/tmp"
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
          name = "tmp"
          empty_dir {
            medium = "Memory"
          }
        }
      }
    }
  }
  wait_for_rollout = false
}

# ── Services and the Route ────────────────────────────────────────────────────
resource "kubernetes_service" "party" {
  for_each = local.parties
  metadata {
    name      = each.value.name
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  spec {
    selector = { "app.kubernetes.io/name" = each.value.name }
    dynamic "port" {
      for_each = each.key == "verifier" ? { enter = 8080, status = 9090 } : { status = 9090 }
      content {
        name        = port.key
        port        = port.value
        target_port = port.key
      }
    }
  }
}

resource "kubernetes_service" "board" {
  metadata {
    name      = "door-board"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  spec {
    selector = { "app.kubernetes.io/name" = "door-board" }
    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }
  }
}

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

# Only the client may knock on the verifier's door.
resource "kubernetes_network_policy" "enter_from_client" {
  metadata {
    name      = "verifier-enter-from-client"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = { "app.kubernetes.io/name" = "door-verifier" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "door-client" }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }
}

# Only the board reads the parties' status.
resource "kubernetes_network_policy" "status_from_board" {
  metadata {
    name      = "status-from-board"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_expressions {
        key      = "shift-gear/door-party"
        operator = "Exists"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "door-board" }
        }
      }
      ports {
        port     = "9090"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy" "board_from_router" {
  metadata {
    name      = "board-from-router"
    namespace = kubernetes_namespace.consumer.metadata[0].name
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = { "app.kubernetes.io/name" = "door-board" }
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

# Additive, one per party (core object untouched): each party's pod may reach
# Vault. Separate objects so a test can cut off one party alone.
resource "kubernetes_network_policy" "vault_from_party" {
  for_each = local.parties
  metadata {
    name      = "allow-sg-rotation-${each.value.name}"
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
          match_labels = { "app.kubernetes.io/name" = each.value.name }
        }
      }
      ports {
        port     = "8200"
        protocol = "TCP"
      }
    }
  }
}

# ── Vault: each party reads the one shared secret, nothing else ─────────────
resource "vault_policy" "party" {
  for_each  = local.parties
  namespace = var.vault_namespace
  name      = each.value.role
  policy    = <<-HCL
    # ${each.value.role} — the Secure Door ${each.key}'s Vault Agent (prompt 01_10).
    # Read the one shared secret (value + version metadata come with it).
    path "kv/data/${var.secret_path}" {
      capabilities = ["read"]
    }
  HCL
}
