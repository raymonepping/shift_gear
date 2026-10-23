# Live seal-chain observation — 23 October 2026

The seal-chain indicator previously depended on `sg-evidence`, a host-published snapshot. Its 120-second expiry correctly withdrew green but made an otherwise healthy running lab appear unverified after two minutes. Reloading the browser could not collect new evidence.

The authenticated runtime observer now reads Seal Vault and each fixed main-member `sys/health` endpoint with the project CA, without a Vault token. It reads only the named `Deployment/seal-agent` status using the existing rotating UI service-account identity. Terraform owns the additional GET-only Role/binding and the namespace-and-pod-selected UI ingress rule to Seal Vault. Access to the Agent's mTLS proxy is unchanged.

The topbar and both Fleet/Cluster diagrams share one foreground polling loop. Checks run every 15 seconds, with a ten-second server cache, shared in-flight collection, three-second upstream deadlines, a 64 KiB upstream limit and a five-second browser deadline without automatic retry. Hidden tabs pause polling and check immediately on return. Each observation expires after 30 seconds; its original timestamp is retained. Failed refreshes withdraw green immediately. Published deployment/history snapshots retain their separate source identity and 120-second expiry.

Green requires all five seal-chain sources fresh, initialized/unsealed Seal Vault and main members, exactly one member reporting active, and the current Agent generation at its desired updated/available replica count. Known sealed/uninitialized Vault health responses remain meaningful negative observations. Missing, invalid, denied or stale sources cannot establish health. A fresh sealed observation remains visible even if another source fails.

Agent readiness does not prove Transit decryption, future auto-unseal or disaster recovery. These checks do not establish Raft quorum or replace `make verify`. Neither optional telemetry backend is required.

## Validation

- Static gate: 18/18, including Terraform mock-provider coverage of the named GET-only role.
- Offline regression suite: 58/58 (27 Python, 21 UI/HTTPS contracts, 10 collector checks).
- UI type-check and lint: passed.
- Actual observer RBAC: 20/20 named allow/deny cases; no Secret read, list/watch, mutation, pod read or exec was granted.
- Terraform foundation apply: two additions and one in-place network-policy update, zero deletions; follow-up plan empty.
- Direct reads from the deployed UI pod: all four Vault endpoints answered with initialized/unsealed metadata, using the configured CA and real internal DNS names.
- An unrelated, unprivileged temporary application pod could reach neither Seal Vault nor the Agent; the pod was removed after the probe.
- Read-only runtime verifier: 18 passed, zero warnings/failures.

- Standard Playwright suite: 154 passed, one accessibility timeout and one planned skip. The exact failed accessibility case passed on an unchanged-source rerun (23.3 seconds), giving 155 passing distinct standard cases across the run and rerun. The duplicate long real-time sampling case is deliberately skipped on mobile; its desktop run passed.
- New browser checks passed on desktop/mobile: Agent failure/recovery, failed request/recovery, and stale retained-response expiry. A real 125-second sampling window stayed green with a deliberately old snapshot, recorded at least six distinct real observations, and required no host publication.
- The authenticated API returned all eleven actual sources without raw upstream payloads; the live UI showed all three members verified unsealed. Desktop/mobile captures were visually reviewed, and existing layout checks passed at 390, 320 and 195 CSS pixels.
- Controlled live failover: 1/1 passed (16.3 seconds). The diagram observed a different active member and all three members recovering without `make ux`.

The first browser timeout is retained in `.cache/seal-chain-browser.log` and `.cache/seal-chain-browser-first/`; its successful rerun is in `.cache/seal-chain-browser-rerun.log`. No assertion or timeout was weakened.

Executable input digest: `6a6f20e230df9f461e62a84cd688c046397e9a3a991b2a36531f179de6a4dea5`. Original cluster UID: `bef1f3e7-a9c6-43bb-9847-a0ee756cd38c`.

The earlier 22 October 43-step manifest remains a historical receipt for its own source digest. This focused follow-up does not replace the full protected release ladder, an isolated restore proof or the explicitly deferred roadmap items.

## Final convergence and health

`make lab` passed for run `018a7803-7fc9-4551-8281-c91f23e19adc` on the original cluster and the unchanged input digest above. Provisioning and evidence publication both finished successfully. The lab's Ansible idempotency gate, all five empty Terraform plans, validation and secret scan passed. Its convergence receipt records `finished_at: 2026-10-23T10:51:25Z` (12:51:25 Amsterdam time); this is an acceptance run, not a new performance benchmark.

After convergence, full `make verify` passed all 23 checks with zero warnings or failures, including current source/run/cluster identity and all convergence gates. Vault token boundaries passed 19/19. A final real API/UI check passed on desktop and mobile (2/2): all eleven runtime sources were available and the indicator showed `Seal chain 3/3`.

Local logs: `.cache/seal-chain-static.log`, `seal-chain-offline.log`, `seal-chain-ui-check.log`, `seal-chain-foundation-plan.log`, `seal-chain-foundation-apply.log`, `seal-chain-boundary.log`, `seal-chain-network.log`, `seal-chain-browser.log`, `seal-chain-browser-rerun.log`, `seal-chain-failover.log`, `seal-chain-lab.log`, `seal-chain-final-verify.log`, `seal-chain-vault-boundary.log` and `seal-chain-final-live.log` (all under `.cache/`). The first browser-run artifacts and reviewed desktop/mobile captures are preserved in `.cache/seal-chain-browser-first/`; final captures are in `ui/test-results/`.

No reset, isolated restore, commit, push, tag or external publication was performed. The historical full release manifest remains unchanged; this follow-up records its own source-bound local acceptance.
