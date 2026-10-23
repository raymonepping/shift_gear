# Scenario 03 — Rotate twice

The proof runs two Jobs from `seal-rotator`. It verifies that the agent holds
a new secret-id, the previous ID is absent, current-ID lookup returns 200,
and exactly one ID remains for `sg-seal-autounseal`.

```sh
make rotation-proof
# Inspect previous-ID absence, current lookup=200, count=1.
# Or run: bash scenarios/03_rotation_proof/run.sh
```

The agent role permits repeated logins (`secret_id_num_uses = 0`) and its ID
expires after 24 hours. The CronJob rotates every six hours. The separate
rotator ID also permits repeated logins and has no expiry. Login from the
controller is refused by the pod-CIDR binding, so lookup/list provide the proof.

Expected evidence is `the agent holds a new secret-id`, `the previous
secret-id is gone`, `the current secret-id exists (lookup 200)`, and
`exactly one secret-id for sg-seal-autounseal`. The previous-ID lookup must return 204 (empty lookup) or 404; an authorization
or server error fails the proof.
