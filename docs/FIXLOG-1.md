# Fix log 1 (answers FEEDBACK-1.md, 15 findings)

Every claim was re-checked against the real harness (`pushbranch.sh`, `resetcluster.sh`, `buildrepl.sh`, `kernelclean.sh`, `stalelooppclean.sh`, helper libraries). No finding was disputed; F-08 is fixed in part (the rest is documented as write-it-yourself).

| Finding | Result | What changed |
|---|---|---|
| F-01 blocker (deploy wiped by reset/join) | FIXED | `tools/code-deploy.sh` rewritten: default `deploy.method: product-push` runs the product's own push into the node software repo, checks the branch arrived, pulls on each node, compares commits, refreshes the version. `--check-branch` is called by `cluster-reset.sh`. `bundle` stays with a warning. Docs: `loop-rules.md` s5, `roles/coder.md` step 5. |
| F-02 (clean-iteration counting) | FIXED | `loop-state.sh`: a failed test dirties the iteration; a clean full iteration counts; `code-change` resets both counters; `is-clean` needs one clean iteration. Selftest cases added. |
| F-03 (kernel clean / stale LIO) | FIXED | `host-kernelclean.sh` removes stale LIO targets and backstores via a helper node or the host, stops with exit 4 when it cannot; `host-stale-clean.sh` writes `none` to the host-side export lists even with nodes stopped. |
| F-04 (replication build missing) | FIXED, partly not portable | New `cluster-build-repl.sh`. The original also recreated a third node container; that is not portable and is documented in the header and `safety.md`. |
| F-05 (set -u unbound variables) | FIXED | All optional variables use `${VAR:-}`; selftest runs under `set -u`. |
| F-06 (DRYRUN not covering host/cluster/API writes) | FIXED | DRYRUN now covers host-kernelclean, host-stale-clean, cluster-reset, cluster-join, cluster-build-repl, ts-disk-add and non-GET `ts_api`. Selftest uses PATH shims that record any mutating call; none is made. README and SKILL wording corrected. |
| F-07 (hard-coded addresses) | FIXED | First-boot and discovery addresses come from the config, no defaults; example config uses `CHANGE_ME`; `cfg.py validate` requires them and node aliases. |
| F-08 (step helpers missing) | FIXED in part | New `ts-pool.sh`, `ts-volume.sh`, `ts-user.sh`, `ts-disk-add.sh`, `ts-disk-remove.sh` (container flavour; others exit 10 NEEDS-HUMAN), `cluster-wait-takeover.sh`, `client-mount-check.sh`, `qc-local.sh`. Replica hot-add, replication/group/domain/flask/balance waits, failover watch and SMB/NFS volume settings are documented in `safety.md` as write-it-yourself with `ts_api`. |
| F-09 (reboot rule) | FIXED | Matches the standing order: reboot allowed for any tool problem or suspended pool, with evidence, others save state first, supervisor approves, no dockerd restart, no sync, step not failed. `safety.md` s5, `SKILL.md`, `roles/supervisor.md`, `roles/tester.md`, config key `loop.reboot_for_tool_problems`. |
| F-10 (iSCSI tools with a pool imported) | FIXED | `repl-iscsi-cross.sh` and `iscsi-stale-clean.sh` refuse when a pool is imported on a listed node. |
| F-11 (flavour/type mismatch, remote docker) | FIXED | `cfg.py validate` errors on a mismatch; `require_local_kernel` refuses host-side tools when a container node uses `docker_host`. |
| F-12 (node-start --wait rc, PR lookup) | FIXED | `node-start --wait` exits 0/1 by result; `git-pr.sh` looks up `pulls?head=<owner>:<branch>`. |
| F-13 (supervisor report) | FIXED | `roles/supervisor.md`: "Waiting for your decision" line; held FAIL and stopped submit are reported at once with evidence. |
| F-14 (counts and docs) | FIXED | `tools/README.md` table lists the new tools; counts are no longer stated as a number. |
| F-15 (config comments and rules) | FIXED | Example config comments updated; `supervisor-snapshot.sh` prints the active rules. |

Verification: `bash -n` on all scripts clean, `tests/selftest.sh` 35 passed 0 failed, `tools/secret-scan.sh` clean.
