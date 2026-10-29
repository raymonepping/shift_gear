# The declarative configuration, parsed once by Terraform and handed to the
# controller as JSON (the runtime is stdlib-only: no YAML parser in the pod).
# The rules below mirror controller/rotation/config.py so a bad file fails at
# plan time, before anything is deployed.

locals {
  doc      = yamldecode(file("${path.module}/${var.config_file}"))
  rotation = local.doc.rotation
  mount    = trimsuffix(lookup(local.rotation, "mount", "kv"), "/")
  prefix   = trim(local.rotation.prefix, "/")

  unit = { s = 1, m = 60, h = 3600, d = 86400 }
  # "60s" -> 60, "5m" -> 300 …  (invalid strings become -1 and fail the checks)
  seconds = {
    for k, v in merge(
      { for t, d in local.rotation.types : "type:${t}:interval" => d.schedule.interval },
      { for t, d in local.rotation.types : "type:${t}:max_age" => d.policy.max_age },
      { for s in local.rotation.secrets : "secret:${s.type}/${s.name}:interval" => s.interval if can(s.interval) },
    ) : k => can(regex("^[0-9]+[smhd]$", v)) ? tonumber(regex("^([0-9]+)", v)[0]) * local.unit[substr(v, -1, 1)] : -1
  }

  secrets = [for s in local.rotation.secrets : {
    id         = "${s.type}/${s.name}"
    rel_path   = "${local.prefix}/${s.type}/${s.name}"
    type       = s.type
    strategies = lookup(s, "strategies", ["time"])
    owner      = lookup(s, "owner", "")
    interval   = lookup(local.seconds, "secret:${s.type}/${s.name}:interval", local.seconds["type:${s.type}:interval"])
    max_age    = local.seconds["type:${s.type}:max_age"]
    events     = [for e in lookup(s, "events", []) : { match = e.match, path = trim(e.path, "/") }]
  }]

  # Watched paths (event cascade): the controller may read their *metadata*
  # and subscribe to their events — never read their data.
  watched_paths = distinct(flatten([for s in local.secrets : [for e in s.events : e.path]]))

  config_json = jsonencode(local.doc)
}

resource "terraform_data" "config_contract" {
  input = sha256(local.config_json)

  lifecycle {
    precondition {
      condition     = alltrue([for k, v in local.seconds : v > 0])
      error_message = "Every interval and max_age must be a duration like 60s, 5m, 2h or 30d."
    }
    precondition {
      condition     = alltrue([for t, d in local.rotation.types : local.seconds["type:${t}:interval"] <= local.seconds["type:${t}:max_age"]])
      error_message = "A type's schedule.interval may not exceed its policy.max_age."
    }
    precondition {
      condition     = alltrue([for s in local.secrets : s.interval <= s.max_age])
      error_message = "A secret's interval override may not loosen its type's max_age."
    }
    precondition {
      condition     = alltrue([for s in local.secrets : contains(keys(local.rotation.types), s.type)])
      error_message = "Every secret must reference a declared type."
    }
    precondition {
      condition     = length(distinct([for s in local.secrets : s.id])) == length(local.secrets)
      error_message = "Secret ids (<type>/<name>) must be unique."
    }
    precondition {
      condition     = alltrue([for p in local.watched_paths : !startswith(p, "${local.prefix}/") && p != local.prefix])
      error_message = "An event rule may not watch the managed prefix (rotation loop)."
    }
    precondition {
      condition     = alltrue(flatten([for s in local.secrets : [for st in s.strategies : contains(["time", "usage", "event"], st)]]))
      error_message = "Strategies are time, usage and event."
    }
    precondition {
      condition     = alltrue([for s in local.secrets : length(s.events) <= 8 && length(join(",", [for e in s.events : "${e.path}@1000000000"])) <= 480])
      error_message = "At most 8 event rules per secret, and the version checkpoint must fit in 480 bytes (custom metadata values hold 512)."
    }
    precondition {
      condition     = alltrue([for s in local.secrets : s.owner == "application"])
      error_message = "Every secret must declare owner: application. Vault-native credentials belong to their engine (signing keys: Transit); external-provider credentials must be rotated by the provider."
    }
    precondition {
      condition     = alltrue([for s in local.secrets : contains(s.strategies, "time")])
      error_message = "Every secret must include the time strategy: its type has a max_age, and usage/event only rotate earlier."
    }
  }
}
