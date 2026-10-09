# terraform/infra/outputs.tf — THE SUBSTRATE CONTRACT.
#
# Every value below can be satisfied by any OpenShift cluster.
# No module above infra/ may reference crc, vfkit, api.crc.testing,
# or any other substrate-specific detail. Consume these outputs only.
#
# Changing the substrate = replace terraform/infra/, make the cluster
# output true, run `make lab`. Nothing above infra changes.

output "cluster" {
  description = "OpenShift cluster connection contract. Stable across substrate implementations."
  value = {
    api_url         = var.api_url
    apps_domain     = local.apps_domain
    pod_cidr        = local.pod_cidr
    kubeconfig_path = var.kubeconfig_path
    ingress_ca_path = local.ingress_ca_path
    registry_host   = "image-registry.openshift-image-registry.svc:5000"
  }
}
