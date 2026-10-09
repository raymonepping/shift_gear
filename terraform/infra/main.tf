# terraform/infra/main.tf — SUBSTRATE CONTRACT ROOT.
#
# This is the ONLY Terraform file that may know about the substrate (CRC today;
# any OpenShift cluster tomorrow). It reads the running cluster and emits the
# contract. No resources are created here.
#
# Lesson 19: only terraform/infra/ and scripts/crc-*.sh may reference
# crc, vfkit, api.crc.testing, or apps-crc.testing. `make check` verifies with grep.

terraform {
  backend "local" {
    # Path is relative to terraform/infra/ (the Terraform working directory)
    path = "../../.secrets/terraform/infra/terraform.tfstate"
  }
}

provider "kubernetes" {
  # kubeconfig_path is relative to the project root; Terraform runs from terraform/infra/
  config_path = abspath("${path.root}/../../${var.kubeconfig_path}")
}

# ---------------------------------------------------------------------------
# Discover the wildcard Route domain from the OpenShift cluster config.
# Field: spec.domain on ingresses.config.openshift.io/cluster
# ---------------------------------------------------------------------------
data "kubernetes_resource" "ingress_config" {
  api_version = "config.openshift.io/v1"
  kind        = "Ingress"

  metadata {
    name = "cluster"
  }
}

# ---------------------------------------------------------------------------
# Discover the cluster network CIDR.
# Field: status.clusterNetwork[0].cidr on networks.config.openshift.io/cluster
# ---------------------------------------------------------------------------
data "kubernetes_resource" "network_config" {
  api_version = "config.openshift.io/v1"
  kind        = "Network"

  metadata {
    name = "cluster"
  }
}

locals {
  apps_domain     = data.kubernetes_resource.ingress_config.object.spec.domain
  pod_cidr        = data.kubernetes_resource.network_config.object.status.clusterNetwork[0].cidr
  ingress_ca_path = ".secrets/kube/ingress-ca.pem"
}

# ---------------------------------------------------------------------------
# The router's CA bundle, for clients of edge/reencrypt Routes (Keycloak, the
# console). Every OpenShift cluster publishes it in
# openshift-config-managed/default-ingress-cert; the contract names the file
# (cluster.ingress_ca_path), and this root makes it true. Public material.
# ---------------------------------------------------------------------------
data "kubernetes_config_map_v1" "ingress_ca" {
  metadata {
    name      = "default-ingress-cert"
    namespace = "openshift-config-managed"
  }
}

resource "local_file" "ingress_ca" {
  filename        = abspath("${path.root}/../../${local.ingress_ca_path}")
  content         = data.kubernetes_config_map_v1.ingress_ca.data["ca-bundle.crt"]
  file_permission = "0644"
}
