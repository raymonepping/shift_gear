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

run "each_party_has_its_own_identity" {
  command = plan

  assert {
    condition     = toset([for sa in kubernetes_service_account.party : sa.metadata[0].name]) == toset(["door-verifier", "door-client"])
    error_message = "Two ServiceAccounts: door-verifier and door-client."
  }

  assert {
    condition     = toset([for p in vault_policy.party : p.name]) == toset(["sg-rotation-door-verifier", "sg-rotation-door-client"])
    error_message = "Two Vault policies, one per party."
  }

  assert {
    condition = alltrue([for k, d in kubernetes_deployment.party :
    d.spec[0].template[0].spec[0].service_account_name == kubernetes_service_account.party[k].metadata[0].name])
    error_message = "Each party runs under its own ServiceAccount."
  }

  assert {
    condition = alltrue([for k, h in local.agent_hcl :
    strcontains(h, "role       = \"${local.parties[k].role}\"") && !strcontains(h, local.parties[k == "verifier" ? "client" : "verifier"].role)])
    error_message = "Each Agent logs in with its own party's role only."
  }
}

run "only_the_agent_holds_vault_identity" {
  command = plan

  assert {
    condition = alltrue(concat(
      [for d in kubernetes_deployment.party : d.spec[0].template[0].spec[0].automount_service_account_token == false],
      [kubernetes_deployment.board.spec[0].template[0].spec[0].automount_service_account_token == false],
    ))
    error_message = "No pod automounts a ServiceAccount token."
  }

  assert {
    condition = alltrue(flatten([for d in kubernetes_deployment.party : [
      for c in d.spec[0].template[0].spec[0].container :
      (c.name == "vault-agent") == anytrue([for m in c.volume_mount : m.name == "vault-token"])
    ]]))
    error_message = "In each party the projected Vault token is mounted into vault-agent and into no other container."
  }

  assert {
    condition = alltrue([for h in values(local.agent_hcl) :
    !can(regex("(?m)^\\s*(sink|listener)\\s+\"", h)) && !can(regex("(?m)^\\s*api_proxy\\s*\\{", h))])
    error_message = "No Agent has a sink, a listener or an api_proxy."
  }

  assert {
    condition = alltrue(flatten([for d in kubernetes_deployment.party : [
      for c in d.spec[0].template[0].spec[0].container :
      contains(["vault-agent", "vault-probe"], c.name) || alltrue([for e in c.env : !startswith(e.name, "VAULT_")])
    ]]))
    error_message = "verifier and client carry no VAULT_* settings."
  }

  assert {
    condition     = length(kubernetes_deployment.board.spec[0].template[0].spec[0].container) == 1 && alltrue([for e in kubernetes_deployment.board.spec[0].template[0].spec[0].container[0].env : !startswith(e.name, "VAULT_")])
    error_message = "The board pod has one container and no Vault settings."
  }
}

run "rendered_secret_is_read_only_where_consumed" {
  command = plan

  assert {
    condition = alltrue(flatten([for k, d in kubernetes_deployment.party : [
      for c in d.spec[0].template[0].spec[0].container : [
        for m in c.volume_mount : m.read_only if c.name == k && contains(["render", "agent-log", "health", "code"], m.name)
      ]
    ]]))
    error_message = "render/agent-log/health/code are read-only in the party container."
  }

  assert {
    condition = alltrue(flatten([for k, d in kubernetes_deployment.party : [
      for c in d.spec[0].template[0].spec[0].container :
      contains(["vault-agent", k], c.name) || !anytrue([for m in c.volume_mount : m.name == "render"])
    ]]))
    error_message = "Only vault-agent (writer) and the party (reader) mount the rendered secret."
  }

  assert {
    condition     = anytrue([for v in kubernetes_deployment.party["client"].spec[0].template[0].spec[0].volume : v.name == "state"]) && !anytrue([for v in kubernetes_deployment.party["verifier"].spec[0].template[0].spec[0].volume : v.name == "state"])
    error_message = "Only the client keeps a (non-secret) state volume."
  }
}

run "grace_is_explicit" {
  command = plan

  variables {
    grace_seconds = 0
  }

  assert {
    condition     = local.party_env.verifier.DOOR_GRACE_SECONDS == "0" && !contains(keys(local.party_env.client), "DOOR_GRACE_SECONDS")
    error_message = "Strict mode is set on the verifier only."
  }
}

run "grace_out_of_range_is_refused" {
  command = plan

  variables {
    grace_seconds = 7200
  }

  expect_failures = [var.grace_seconds]
}

run "hardened_and_pinned" {
  command = plan

  assert {
    condition = alltrue([
      for c in concat(flatten([for d in kubernetes_deployment.party : d.spec[0].template[0].spec[0].container]), kubernetes_deployment.board.spec[0].template[0].spec[0].container) :
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
    condition = alltrue([for p in vault_policy.party :
      length(regexall("(?m)^\\s*path\\s+\"", p.policy)) == 1 && strcontains(p.policy, "path \"kv/data/shift-gear/rotation/api-key/secure-door\"") &&
    strcontains(p.policy, "[\"read\"]") && !can(regex("path \"[^\"]*\\*", p.policy))])
    error_message = "Each party's policy reads exactly one secret."
  }

  assert {
    condition = alltrue([for k, np in kubernetes_network_policy.vault_from_party :
      np.metadata[0].namespace == "sg-vault" && np.metadata[0].name == "allow-sg-rotation-${local.parties[k].name}" &&
    np.metadata[0].labels["shift-gear/addon"] == "rotation-consumer" && np.spec[0].ingress[0].from[0].pod_selector[0].match_labels["app.kubernetes.io/name"] == local.parties[k].name])
    error_message = "One additive, add-on labelled Vault allow per party, scoped to that party's pod."
  }

  assert {
    condition     = kubernetes_network_policy.enter_from_client.spec[0].ingress[0].from[0].pod_selector[0].match_labels["app.kubernetes.io/name"] == "door-client" && kubernetes_network_policy.enter_from_client.spec[0].ingress[0].ports[0].port == "8080" && kubernetes_network_policy.enter_from_client.spec[0].pod_selector[0].match_labels["app.kubernetes.io/name"] == "door-verifier"
    error_message = "Only the client reaches the verifier's /enter (8080)."
  }

  assert {
    condition     = kubernetes_network_policy.status_from_board.spec[0].ingress[0].from[0].pod_selector[0].match_labels["app.kubernetes.io/name"] == "door-board" && kubernetes_network_policy.status_from_board.spec[0].ingress[0].ports[0].port == "9090"
    error_message = "Only the board reads the parties' /status (9090)."
  }

  assert {
    condition     = length(coalesce(kubernetes_network_policy.default_deny.spec[0].pod_selector[0].match_labels, {})) == 0 && kubernetes_network_policy.default_deny.spec[0].policy_types == tolist(["Ingress"])
    error_message = "Ingress is denied by default in the namespace."
  }

  assert {
    condition     = kubernetes_manifest.route.manifest.spec.host == "secure-door.apps.example.local" && kubernetes_manifest.route.manifest.spec.tls.termination == "edge" && kubernetes_manifest.route.manifest.spec.to.name == "door-board"
    error_message = "The Route is secure-door.<apps_domain>, edge TLS, to the board."
  }
}
