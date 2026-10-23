# Optional preferred adapter. No operator, API token or persistent metrics store.
# Prometheus is the wire format here; no Prometheus server is required.
resource "kubernetes_config_map_v1" "otel" {
  count = var.metrics_backend == "opentelemetry" ? 1 : 0
  metadata {
    name      = "sg-otel-config"
    namespace = "sg-app"
    labels    = local.labels
  }
  data = {
    "collector.yml" = yamlencode({
      receivers = {
        prometheus = { config = { scrape_configs = [{
          job_name        = "sg-audit"
          scrape_interval = "10s"
          scrape_timeout  = "3s"
          sample_limit    = 64
          label_limit     = 4
          static_configs  = [{ targets = ["sg-audit.sg-app.svc:8081"] }]
        }] } }
      }
      processors = { memory_limiter = { check_interval = "1s", limit_mib = 96, spike_limit_mib = 24 }, batch = { timeout = "1s", send_batch_size = 64 } }
      exporters = { prometheus = {
        endpoint                         = "0.0.0.0:9090"
        send_timestamps                  = true
        metric_expiration                = "60s"
        resource_to_telemetry_conversion = { enabled = false }
      } }
      extensions = { health_check = { endpoint = "0.0.0.0:13133" } }
      service = {
        extensions = ["health_check"]
        pipelines  = { metrics = { receivers = ["prometheus"], processors = ["memory_limiter", "batch"], exporters = ["prometheus"] } }
        telemetry  = { logs = { level = "warn" } }
      }
    })
  }
}

resource "kubernetes_deployment_v1" "otel" {
  count = var.metrics_backend == "opentelemetry" ? 1 : 0
  metadata {
    name      = "sg-otel"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector { match_labels = { "app.kubernetes.io/name" = "sg-otel" } }
    template {
      metadata {
        labels      = merge(local.labels, { "app.kubernetes.io/name" = "sg-otel", "shift-gear/audit-metrics-reader" = "true" })
        annotations = { "openshift.io/required-scc" = "restricted-v2", "shift-gear/config-sha256" = sha256(kubernetes_config_map_v1.otel[0].data["collector.yml"]) }
      }
      spec {
        automount_service_account_token = false
        security_context {
          run_as_non_root = true
          seccomp_profile { type = "RuntimeDefault" }
        }
        container {
          name  = "otel-collector"
          image = "docker.io/otel/opentelemetry-collector-contrib@sha256:1175b03003053962012f5a231f5567f66a3e8fdb960c7835c0e48f7aa1555806"
          args  = ["--config=/etc/sg-otel/collector.yml"]
          port {
            name           = "metrics"
            container_port = 9090
          }
          readiness_probe {
            http_get {
              path = "/"
              port = 13133
            }
            period_seconds = 5
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { memory = "160Mi" }
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/sg-otel"
            read_only  = true
          }
        }
        volume {
          name = "config"
          config_map { name = kubernetes_config_map_v1.otel[0].metadata[0].name }
        }
      }
    }
  }
  # An optional integration must not block core workload reconciliation.
  wait_for_rollout = false
}

resource "kubernetes_service_v1" "otel" {
  count = var.metrics_backend == "opentelemetry" ? 1 : 0
  metadata {
    name      = "sg-otel"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    selector = { "app.kubernetes.io/name" = "sg-otel" }
    port {
      name        = "metrics"
      port        = 9090
      target_port = 9090
    }
  }
}

resource "kubernetes_network_policy_v1" "otel" {
  count = var.metrics_backend == "opentelemetry" ? 1 : 0
  metadata {
    name      = "sg-otel-ingress"
    namespace = "sg-app"
    labels    = local.labels
  }
  spec {
    pod_selector { match_labels = { "app.kubernetes.io/name" = "sg-otel" } }
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector { match_labels = { "app.kubernetes.io/name" = "sg-ui" } }
      }
      ports {
        port     = 9090
        protocol = "TCP"
      }
    }
  }
}
