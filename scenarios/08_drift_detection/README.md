# Scenario 08 — Drift detection

Prove detection with four reversible mutations. Each mutation is asserted
before checking, each detector must report the specific change, and each
restoration is checked. No secret engine or database data is deleted.

```sh
bash scenarios/08_drift_detection/run.sh
make drift
```

| Mutation | Detection | Restoration |
|---|---|---|
| Transit mount description | Platform plan exits 2 and names the mount and marker | Platform apply, then read-back |
| Extra workload-a Deployment label | Workloads plan exits 2 and names the label | Workloads apply, then read-back |
| sg-cli client name | Identity check mode reports changes and leaves marker intact | Real identity run, then read-back |
| Ben added to engineers | Fresh LDAP login gains `sg-engineer`; `staff` deliberately carries no policy | Remove membership; fresh login has no identity policy |

The run requires clean platform and workloads plans first. It finishes with
clean plans and the full identity verifier. A cleanup handler reverses a
mutation if its proof fails. Credentials stay in memory or stdin; captured
command output goes to ignored `.cache/scenario-08-*.log` files. Inspect those
logs if a check fails, then confirm `make verify` and `make drift`.
