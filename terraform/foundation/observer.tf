# UI observation can GET only five named resources. No list, watch,
# Secrets, pod exec, bootstrap credential or cluster-wide role.
resource "kubernetes_service_account_v1" "ui_observer" {
  metadata {
    name      = "sg-ui-observer"
    namespace = "sg-app"
    labels    = local.labels
  }
  # OpenShift owns only these registry credential references and marker.
  lifecycle {
    ignore_changes = [image_pull_secret, secret, metadata[0].annotations["openshift.io/internal-registry-pull-secret-ref"]]
  }
  automount_service_account_token = false
  depends_on                      = [kubernetes_namespace.sg_app, kubernetes_namespace.sg_workloads]
}

resource "kubernetes_role_v1" "ui_observer" {
  metadata {
    name      = "sg-ui-observer"
    namespace = "sg-workloads"
    labels    = local.labels
  }
  rule {
    api_groups     = ["secrets.hashicorp.com"]
    resources      = ["vaultstaticsecrets"]
    resource_names = ["app-config"]
    verbs          = ["get"]
  }
  rule {
    api_groups     = ["secrets.hashicorp.com"]
    resources      = ["vaultdynamicsecrets"]
    resource_names = ["db-creds"]
    verbs          = ["get"]
  }
  rule {
    api_groups     = ["apps"]
    resources      = ["deployments"]
    resource_names = ["workload-a", "workload-b"]
    verbs          = ["get"]
  }
  depends_on = [kubernetes_namespace.sg_app, kubernetes_namespace.sg_workloads]
}

resource "kubernetes_role_binding_v1" "ui_observer" {
  metadata {
    name      = "sg-ui-observer"
    namespace = "sg-workloads"
    labels    = local.labels
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.ui_observer.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ui_observer.metadata[0].name
    namespace = "sg-app"
  }
}

# Agent availability is public Deployment status, never its credentials or exec.
resource "kubernetes_role_v1" "ui_seal_observer" {
  metadata {
    name      = "sg-ui-seal-observer"
    namespace = "sg-vault-seal"
    labels    = local.labels
  }
  rule {
    api_groups     = ["apps"]
    resources      = ["deployments"]
    resource_names = ["seal-agent"]
    verbs          = ["get"]
  }
  depends_on = [kubernetes_namespace.sg_vault_seal]
}

resource "kubernetes_role_binding_v1" "ui_seal_observer" {
  metadata {
    name      = "sg-ui-seal-observer"
    namespace = "sg-vault-seal"
    labels    = local.labels
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.ui_seal_observer.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ui_observer.metadata[0].name
    namespace = "sg-app"
  }
}
