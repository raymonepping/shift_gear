# Vault structure for the add-on (sg-tf-platform). Auth roles and identity
# groups are configuration and belong to the add-on's Ansible (sg-ansible-platform).

resource "vault_policy" "controller" {
  namespace = var.vault_namespace
  name      = "sg-rotation-controller"
  policy = templatefile("${path.module}/../policies/sg-rotation-controller.hcl.tpl", {
    mount         = local.mount
    prefix        = local.prefix
    watched_paths = local.watched_paths
  })
}

resource "vault_policy" "operator" {
  namespace = var.vault_namespace
  name      = "sg-rotation-operator"
  policy = templatefile("${path.module}/../policies/sg-rotation-operator.hcl.tpl", {
    mount  = local.mount
    prefix = local.prefix
  })
}

resource "vault_policy" "auditor" {
  namespace = var.vault_namespace
  name      = "sg-rotation-auditor"
  policy = templatefile("${path.module}/../policies/sg-rotation-auditor.hcl.tpl", {
    mount  = local.mount
    prefix = local.prefix
  })
}
