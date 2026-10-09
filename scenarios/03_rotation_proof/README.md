# Scenario 03 — Rotate twice (rotation proof)

**Purpose**: Prove the seal agent AppRole secret-id rotation is correct: the old secret-id is rejected (400), the current one is accepted (200), and exactly one valid accessor exists.

## 3-line presenter script

```bash
make rotation-proof
# observe: secret-id-1 → 400, secret-id-2 → 200, accessor count = 1
```

## How to run

```bash
bash scenarios/03_rotation_proof/run.sh
# or:
make rotation-proof
```

## Expected output

```
==> rotation-proof: rotate seal-agent secret-id twice
 ok   secret-id-1 rejected → HTTP 400 ✓
 ok   secret-id-2 accepted → HTTP 200 ✓
 ok   exactly 1 valid accessor ✓
 ok rotation-proof: PASS (rotated twice, old=rejected, current=200, count=1)
```

## Why this works

`seal-autounseal` AppRole has `secret_id_num_uses=1` — each issued secret-id can be consumed exactly once for login.  After the agent uses it to authenticate, any further login attempt with the same secret-id fails with 400.  The rotator mints a fresh one on a 6-hour schedule (CronJob), keeping exactly one valid accessor on the role.
