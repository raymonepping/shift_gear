# sg-rotation-kv — Sentinel EGP for the KV rotation add-on (ADR D18).
# Rendered by addons/rotation/terraform/sentinel.tf from rotation.yaml:
# schedule, generator and enforcement share one source.
#
# Governs kv/data/${prefix}/* and kv/metadata/${prefix}/* in namespace
# shift-gear. Root tokens are not subject to EGPs (break-glass by design).
import "strings"

prefix_data = "${mount}/data/${prefix}/"
prefix_meta = "${mount}/metadata/${prefix}/"

# Per type: minimum length and the generator's alphabet.
types = {
%{ for name, t in types ~}
  "${name}": { "min_length": ${t.min_length}, "pattern": "${t.pattern}" },
%{ endfor ~}
}

# The controller, and only the controller: its policy AND the Kubernetes auth
# metadata of its ServiceAccount. A policy name alone could be attached
# elsewhere; a token for this ServiceAccount comes only from Kubernetes auth.
from_controller = rule {
  "sg-rotation-controller" in token.policies and
  (token.metadata.service_account_namespace else "") is "${k8s_namespace}" and
  (token.metadata.service_account_name else "") is "rotation-controller"
}

path = request.path
is_data  = strings.has_prefix(path, prefix_data) or strings.has_prefix(path, "${vault_namespace}/" + prefix_data)
is_meta  = strings.has_prefix(path, prefix_meta) or strings.has_prefix(path, "${vault_namespace}/" + prefix_meta)
is_write = request.operation in ["create", "update", "patch"]

rel = strings.trim_prefix(strings.trim_prefix(path, "${vault_namespace}/"), prefix_data)
type_name = strings.split(rel, "/")[0]
value = request.data.data.value else ""

value_ok = rule {
  type_name in keys(types) and
  length(value) >= types[type_name].min_length and
  value matches types[type_name].pattern
}

cas_given = rule {
  (request.data.options.cas else null) is not null
}

# 1–3: a value under the prefix is written by the controller, with CAS, and
# meets its type's policy.
data_ok = rule when is_data and is_write {
  from_controller and cas_given and value_ok
}

# 4: anyone else may only *request* a rotation: a metadata patch that touches
# custom_metadata.rotation_request and nothing else. Deleting metadata (and
# with it every version and the history) is refused for everyone.
request_only = rule {
  keys(request.data) == ["custom_metadata"] and
  keys(request.data.custom_metadata) == ["rotation_request"]
}

meta_ok = rule when is_meta {
  request.operation is not "delete" and
  (not is_write or from_controller or request_only)
}

main = rule {
  data_ok and meta_ok
}
