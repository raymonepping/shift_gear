# C02 local destination: private numeric metrics and bounded projected metadata.
# These stores survive pod replacement, not loss of the CRC host/storage.
resource "kubernetes_persistent_volume_claim_v1" "audit_archive" {
  count            = var.observability_storage_enabled ? 1 : 0
  wait_until_bound = false
  metadata {
    name      = "sg-audit-archive"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "128Mi" }
    }
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_persistent_volume_claim_v1" "metrics" {
  count            = var.observability_storage_enabled ? 1 : 0
  wait_until_bound = false
  metadata {
    name      = "sg-metrics-data"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "1Gi" }
    }
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_config_map_v1" "metrics" {
  count = var.metrics_backend == "prometheus" ? 1 : 0
  metadata {
    name      = "sg-metrics-config"
    namespace = "sg-app"
    labels    = local.labels
  }
  data = {
    "prometheus.yml" = yamlencode({
      global = { scrape_interval = "10s", scrape_timeout = "3s" }
      scrape_configs = [{
        job_name       = "sg-audit"
        sample_limit   = 64
        label_limit    = 4
        static_configs = [{ targets = ["sg-audit.sg-app.svc:8081"] }]
      }]
    })
  }
}

resource "kubernetes_deployment_v1" "metrics" {
  count = var.metrics_backend == "prometheus" ? 1 : 0
  metadata {
    name      = "sg-metrics"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = { "app.kubernetes.io/name" = "sg-metrics" }
    }
    template {
      metadata {
        labels = merge(local.labels, { "app.kubernetes.io/name" = "sg-metrics", "shift-gear/audit-metrics-reader" = "true" })
        annotations = {
          "openshift.io/required-scc" = "restricted-v2"
          "shift-gear/config-sha256"  = sha256(kubernetes_config_map_v1.metrics[0].data["prometheus.yml"])
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
          name  = "prometheus"
          image = "docker.io/prom/prometheus@sha256:aafa9d694e6a883c02db516d9f6e5b84e14195f49a2a6456a4cca815edda72b9"
          args = [
            "--config.file=/etc/sg-metrics/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
            "--storage.tsdb.retention.time=7d",
            "--storage.tsdb.retention.size=128MB",
            "--web.listen-address=:9090",
          ]
          port {
            name           = "http"
            container_port = 9090
          }
          readiness_probe {
            http_get {
              path = "/-/ready"
              port = 9090
            }
            period_seconds = 5
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = { cpu = "10m", memory = "64Mi" }
            limits   = { memory = "256Mi" }
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/sg-metrics"
            read_only  = true
          }
          volume_mount {
            name       = "data"
            mount_path = "/prometheus"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.metrics[0].metadata[0].name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.metrics[0].metadata[0].name
          }
        }
      }
    }
  }
  wait_for_rollout = false
}

resource "kubernetes_service_v1" "metrics" {
  count = var.metrics_backend == "prometheus" ? 1 : 0
  metadata {
    name      = "sg-metrics"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    selector = { "app.kubernetes.io/name" = "sg-metrics" }
    port {
      name        = "http"
      port        = 9090
      target_port = 9090
    }
  }
}

resource "kubernetes_network_policy_v1" "metrics" {
  count = var.metrics_backend == "prometheus" ? 1 : 0
  metadata {
    name      = "sg-metrics-ingress"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = { "app.kubernetes.io/name" = "sg-metrics" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "sg-ui" }
        }
      }
      ports {
        port     = 9090
        protocol = "TCP"
      }
    }
  }
}

# Existing lab stores are adopted without recreation; disabling runtime preserves them.
moved {
  from = kubernetes_persistent_volume_claim_v1.audit_archive
  to   = kubernetes_persistent_volume_claim_v1.audit_archive[0]
}
moved {
  from = kubernetes_persistent_volume_claim_v1.metrics
  to   = kubernetes_persistent_volume_claim_v1.metrics[0]
}
moved {
  from = kubernetes_config_map_v1.metrics
  to   = kubernetes_config_map_v1.metrics[0]
}
moved {
  from = kubernetes_deployment_v1.metrics
  to   = kubernetes_deployment_v1.metrics[0]
}
moved {
  from = kubernetes_service_v1.metrics
  to   = kubernetes_service_v1.metrics[0]
}
moved {
  from = kubernetes_network_policy_v1.metrics
  to   = kubernetes_network_policy_v1.metrics[0]
}
