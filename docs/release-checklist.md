# Release checklist

## Current delivery status

Local acceptance passed on 2026-10-15: all 36 live-proof steps, including all nine scenarios and final convergence/drift. Exact source/run/cluster identities are in the [Must delivery record](must-progress.md). M06 isolated recovery is explicitly owner-deferred; this release must not claim data restoration was proved. The receipt has `dirty=true` and cannot satisfy the protected release gate. The selected Should increment passed all 41 ordered steps locally on 2026-10-16; see the [Should delivery record](should-progress.md#final-local-acceptance--2026-10-16) for the exact receipt and retained limits. It also records `dirty=true` and does not replace protected live CI. A historical 36-step receipt cannot authorize that changed revision.

Read-only GitHub inspection on 2026-10-16 found no repository self-hosted runners, no `shift-gear-lab` environment, and no published `live-proof.yml` workflow. Protected execution therefore needs setup and publication before dispatch. No runner, environment, branch, commit, tag or release was created by that inspection.

## Prepare the reviewed revision

- [ ] Review the complete change set, including new untracked delivery files. Keep `.secrets/`, `.cache/`, `.build/`, browser auth states, private traces and historical state/TLS backups outside Git and release artifacts.
- [ ] Run `make check`, `make must-test`, `make ui-check`, `SG_SCAN_MODE=offline ./scripts/secret-scan.sh` and `git diff --check`. The offline scan does not replace the protected live scan.
- [ ] Review the `[Unreleased]` changelog entries and choose the version. Move the entries to that version only when preparing the release.
- [ ] Commit and merge the reviewed changes to `main`; record the exact commit SHA to test. Changes to proof inputs require new evidence.

## Prepare the protected live environment

- [ ] Register a dedicated self-hosted runner with label `shift-gear-lab`, using an operator account with the required existing lab permissions and toolchain. Do not run untrusted pull-request code on this runner.
- [ ] Create GitHub environment `shift-gear-lab` and configure reviewer/deployment-branch protections appropriate to repository policy. Confirm those protections before dispatch.
- [ ] Set environment variable `SHIFT_GEAR_WORKDIR` to the absolute path of the reviewed checkout containing the operator-managed private prerequisites. Do not store credential contents in this variable.
- [ ] Set that checkout to the requested revision with a clean `git status --porcelain`. The workflow deliberately does not run checkout or delete an operator's files.
- [ ] Confirm the target cluster UID, runtime selection, capacity and custody with `make doctor`. Doctor reports individual states; review its output rather than treating its exit status alone as readiness proof. Hold the host awake for the complete run.
- [ ] If the operator intentionally retains concurrent Podman, supply `ALLOW_PODMAN=1` in the runner's controlled environment. Do not stop or switch an existing runtime implicitly.

The protected ladder rotates credentials and leaf certificates, deletes/restarts pods, makes reversible drift mutations, and stops/starts the existing CRC VM. Schedule it while the lab can be interrupted. It does not reset or restore the lab. Private prerequisites remain under operator custody; configure the runner using GitHub's runner setup instructions rather than putting registration credentials in repository files.

## Execute and review the proof

After the workflow exists on the reviewed branch, the operator can dispatch it with:

```sh
gh workflow run live-proof.yml --ref main
gh run list --workflow live-proof.yml --limit 5
```

- [ ] Confirm the dispatched SHA equals the clean runner checkout. Do not change source inputs while proof is executing.
- [ ] Require the complete `Protected live proof` workflow to succeed. Inspect the sanitized `shift-gear-live-proof` artifact: live scope, `pass`, `dirty=false`, matching revision/input digest, target/run identity and complete successful steps.
- [ ] Preserve the successful workflow/run link and reviewed sanitized receipt. The artifact retention is 14 days; plan tagging within that window or retain an approved copy for records and rerun when the gate needs a fresh artifact.
- [ ] Check CRC/OpenShift and individual Vault states after the run, and preserve the selected host runtimes. Record any separately deferred scope.

## Tag and release

- [ ] Tag exactly the commit that passed protected proof; a later documentation commit is a different revision and also needs matching proof. Decide patch/minor/major before using the repository's release helper.
- [ ] Run `commit_gh --release <patch|minor|major>` or the explicitly selected version only after reviewing whether the helper creates a new commit. If it does, obtain proof for that resulting commit before pushing its tag.
- [ ] Confirm the Release workflow downloads the successful protected receipt and passes `scripts/verify-proof.py` before creating the GitHub release. Do not bypass it with a manual release.
- [ ] Confirm release notes accurately state the recovery deferral and operational limits.

## After release

- [ ] Retain the release's workflow/run reference and sanitized proof under the chosen retention policy.
- [ ] Open a fresh `[Unreleased]` changelog section after the released revision is fixed.
- [ ] Announce only when requested by the owner.

C04 also passed the 41-step local ladder on 2026-10-17; its [delivery record](c04-progress.md#final-local-acceptance--2026-10-17) records 138 browser tests and the exact source/run identities. This receipt remains dirty-workspace local evidence; protected live CI and clean-revision release provenance are still required.

For C02/C03, inspect the manifest's `optionalObservability` selection and the matching observability/consumer receipts. Optional disabled status is not enabled export/retention evidence. Compare the non-secret local selection file and input digest; retain protected data when disabling runtime. See [current delivery status](c02-c03-progress.md).

C02/C03 local acceptance (2026-10-22) passed 43/43 steps, 148 standard browser tests and all nine scenarios, with the original cluster UID retained. The accepted receipt is dirty-workspace local evidence; protected release execution remains deferred. [Exact final identities and limits](c02-c03-progress.md#final-local-acceptance--2026-10-22).
