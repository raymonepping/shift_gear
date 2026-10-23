resource "kubernetes_service_account_v1" "agent_db" {
  metadata {
    name      = "sg-agent-db"
    namespace = kubernetes_namespace.sg_workloads.metadata[0].name
    labels    = local.labels
  }
  automount_service_account_token = false
  lifecycle {
    ignore_changes = [image_pull_secret, secret, metadata[0].annotations["openshift.io/internal-registry-pull-secret-ref"]]
  }
}
