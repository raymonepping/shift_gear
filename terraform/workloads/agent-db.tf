# One C03 fixture, not a general onboarding framework. Values never enter state.
resource "kubernetes_config_map_v1" "agent_db" {
  metadata {
    name      = "sg-agent-db-config"
    namespace = "sg-workloads"
    labels    = local.labels
  }
  data = {
    "agent.hcl"    = file("${path.module}/../../deploy/agent-db/agent.hcl")
    "pgpass.ctmpl" = file("${path.module}/../../deploy/agent-db/pgpass.ctmpl")
    "consume.sh"   = file("${path.module}/../../deploy/agent-db/consume.sh")
  }
}

resource "kubernetes_deployment_v1" "agent_db" {
  metadata {
    name      = "sg-agent-db"
    namespace = "sg-workloads"
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = { "app.kubernetes.io/name" = "sg-agent-db" }
    }
    template {
      metadata {
        labels = merge(local.labels, { "app.kubernetes.io/name" = "sg-agent-db" })
        annotations = {
          "openshift.io/required-scc" = "restricted-v2"
          "shift-gear/config-sha256"  = sha256(jsonencode(kubernetes_config_map_v1.agent_db.data))
        }
      }
      spec {
        service_account_name            = "sg-agent-db"
        automount_service_account_token = false
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name  = "vault-agent"
          image = "docker.io/hashicorp/vault-enterprise:2.1.0-ent@sha256:12c3ac1469d11da17747927128ed11bce825a012d3ce13b066d0442d0105df0a"
          args  = ["agent", "-config=/vault/config/agent.hcl"]
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { memory = "128Mi" }
          }
          volume_mount {
            name       = "config"
            mount_path = "/vault/config"
            read_only  = true
          }
          volume_mount {
            name       = "ca"
            mount_path = "/vault/ca"
            read_only  = true
          }
          volume_mount {
            name       = "identity"
            mount_path = "/var/run/sg-agent"
            read_only  = true
          }
          volume_mount {
            name       = "credentials"
            mount_path = "/vault/secrets"
          }
        }
        container {
          name    = "consumer"
          image   = "registry.redhat.io/rhel9/postgresql-16@sha256:791a6f14563178d1bbcd3515bc7dc80c1ae0788a829ff26551cdedbf8f50f0d2"
          command = ["sh", "/opt/consumer/consume.sh"]
          readiness_probe {
            exec {
              command = ["sh", "-c", "test -f /tmp/ready"]
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
            requests = { cpu = "5m", memory = "16Mi" }
            limits   = { memory = "64Mi" }
          }
          volume_mount {
            name       = "config"
            mount_path = "/opt/consumer"
            read_only  = true
          }
          volume_mount {
            name       = "credentials"
            mount_path = "/vault/secrets"
            read_only  = true
          }
          volume_mount {
            name       = "health"
            mount_path = "/tmp"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.agent_db.metadata[0].name
          }
        }
        volume {
          name = "ca"
          config_map {
            name = "sg-ca"
          }
        }
        volume {
          name = "identity"
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
          name = "credentials"
          empty_dir {
            medium     = "Memory"
            size_limit = "1Mi"
          }
        }
        volume {
          name = "health"
          empty_dir {
            medium     = "Memory"
            size_limit = "8Mi"
          }
        }
      }
    }
  }
  # Auth/DB values are configured after workloads; Ansible asserts readiness.
  wait_for_rollout = false
}
