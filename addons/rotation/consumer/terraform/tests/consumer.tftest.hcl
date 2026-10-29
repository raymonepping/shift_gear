# Shape tests for the Secure Door consumer root. Mock providers; no cluster, no Vault.

mock_provider "vault" {}
mock_provider "kubernetes" {
  mock_data "kubernetes_config_map" {
    defaults = {
      data = { "ca.pem" = "-----BEGIN CERTIFICATE-----\nMOCK\n-----END CERTIFICATE-----\n" }
    }
  }
}

override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = {
      cluster = {
        api_url         = "https://api.example.local:6443"
        apps_domain     = "apps.example.local"
        pod_cidr        = "10.217.0.0/22"
        kubeconfig_path = ".secrets/kube/config"
        ingress_ca_path = ".secrets/kube/ingress-ca.pem"
        registry_host   = "image-registry.openshift-image-registry.svc:5000"
      }
    }
  }
}

run "only_the_agent_holds_vault_identity" {
  command = plan

  assert {
    condition     = kubernetes_deployment.door.spec[0].template[0].spec[0].automount_service_account_token == false
    error_message = "The pod must not automount a ServiceAccount token."
  }

  assert {
    condition = alltrue([
      for c in kubernetes_deployment.door.spec[0].template[0].spec[0].container :
      (c.name == "vault-agent") == anytrue([for m in c.volume_mount : m.name == "vault-token"])
    ])
    error_message = "The projected Vault token is mounted into vault-agent and into no other container."
  }

  assert {
    condition     = !can(regex("(?m)^\\s*(sink|listener)\\s+\"", local.agent_hcl)) && !can(regex("(?m)^\\s*api_proxy\\s*\\{", local.agent_hcl))
    error_message = "The Agent has no sink, no listener and no api_proxy."
  }

  assert {
    condition = alltrue([
      for c in kubernetes_deployment.door.spec[0].template[0].spec[0].container :
      c.name == "vault-agent" || c.name == "vault-probe" || alltrue([for e in c.env : !startswith(e.name, "VAULT_")])
    ])
    error_message = "consumer and board carry no VAULT_* settings."
  }
}

run "shared_volumes_are_read_only_where_consumed" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for c in kubernetes_deployment.door.spec[0].template[0].spec[0].container : [
        for m in c.volume_mount : m.read_only if
        (c.name == "consumer" && contains(["render", "agent-log", "health"], m.name)) ||
        (c.name == "board" && m.name == "status")
      ]
    ]))
    error_message = "render/agent-log/health are read-only in consumer; status is read-only in board."
  }

  assert {
    condition = alltrue([
      for c in kubernetes_deployment.door.spec[0].template[0].spec[0].container :
      c.name == "consumer" || !anytrue([for m in c.volume_mount : m.name == "render"]) || c.name == "vault-agent"
    ])
    error_message = "Only vault-agent (writer) and consumer (reader) mount the rendered secret."
  }
}

run "hardened_and_pinned" {
  command = plan

  assert {
    condition = alltrue([
      for c in kubernetes_deployment.door.spec[0].template[0].spec[0].container :
      c.security_context[0].run_as_non_root && c.security_context[0].read_only_root_filesystem &&
      !c.security_context[0].allow_privilege_escalation && contains(c.security_context[0].capabilities[0].drop, "ALL") &&
      can(regex("@sha256:[0-9a-f]{64}$", c.image)) && c.resources[0].limits["memory"] != null
    ])
    error_message = "Every container: non-root, read-only root, no escalation, drop ALL, digest-pinned, memory limit."
  }
}

run "least_privilege_and_scoped_network" {
  command = plan

  assert {
    condition     = length(regexall("(?m)^\\s*path\\s+\"", vault_policy.consumer.policy)) == 1 && strcontains(vault_policy.consumer.policy, "path \"kv/data/shift-gear/rotation/api-key/secure-door\"") && strcontains(vault_policy.consumer.policy, "[\"read\"]") && !can(regex("path \"[^\"]*\\*", vault_policy.consumer.policy))
    error_message = "The consumer policy reads exactly one secret."
  }

  assert {
    condition     = kubernetes_network_policy.vault_from_consumer.metadata[0].namespace == "sg-vault" && kubernetes_network_policy.vault_from_consumer.metadata[0].labels["shift-gear/addon"] == "rotation-consumer"
    error_message = "The Vault allow is additive and add-on labelled."
  }

  assert {
    condition     = kubernetes_manifest.route.manifest.spec.host == "secure-door.apps.example.local" && kubernetes_manifest.route.manifest.spec.tls.termination == "edge"
    error_message = "The board Route is host secure-door.<apps_domain> with edge TLS."
  }
}
