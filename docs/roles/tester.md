# Role brief: QC TESTER

## Goal
Run ONE platform test (the active one) on the configured nodes, step by step; submit every step once as soon as it is done; end
with a DONE line, then stop.

## Inputs
`SKILL.md` 1.2, `docs/loop-rules.md`, `docs/safety.md`, `docs/platform-api.md`, `docs/pitfalls.md`, the task from the supervisor
(test id, iteration, round dir if this is a RESUME, build tag).

## Steps
1. `tools/preflight.sh` (rc 2: stop and report the missing config fields).
2. New test: `R=$(tools/round-new.sh <test> <iteration>)`; RESUME: read `state/rounds/<round>/RESUME.md`, `run.log`, the build status,
   the ledger `state/ledger/<round>.sent`; let a running build finish; never start a second build.
   If a restart killed the build (lock free, status not DONE/STOP, no `docker_setup` running in the nodes) the build tools answer REFUSED rc 5:
   then `QC_BUILD_RESTART=1 tools/cluster-reset.sh <N> ...` starts it over on purpose; log it in `run.log`.
3. Read ALL steps (`state/rounds/$R/steps.txt`). Plan which nodes, clusters, disks and clients the test needs and the stop order
   (iSCSI initiator holder last).
4. Stop every cluster node with `tools/cluster-stopnode.sh` (`FORCE_DEGRADED=1` only for a leftover degraded pool). Container
   flavour: `tools/host-stale-clean.sh`; `tools/client-mount-check.sh` (rc 1 = stale NFS/CIFS mount in a client: clean it first).
5. Build: `tools/cluster-reset.sh <build> [--single] [--no-disks]` (replication: `tools/cluster-build-repl.sh <build>` builds both clusters; it cannot recreate a third container, see its header);
   `tools/cluster-refreshcversion.sh`. `tools/qc-start.sh <test>`.
6. Per step: do it with the node wrappers and the TopStor API (`tools/ts-pool.sh`, `ts-volume.sh`, `ts-user.sh`, `ts-disk-add.sh`, `cluster-wait-takeover.sh`; a local re-run is recorded with `tools/qc-local.sh`, never submitted); `tools/cluster-settle.sh` after every start/return and before every
   stop; evidence from real output; write the comment to a file; `tools/qc-submit.sh $R <test> <step id> pass <file> [--config]`.
   The step "upload the config files of all the nodes" and every FAIL use `--config`.
7. A step you cannot pass: `tools/log.sh $R HOLD "<step in words>: <what happened>"`, update RESUME.md, message the supervisor
   (`tools/mailbox.sh send tester-<id> supervisor ...`) with the raw evidence paths, and wait. With a validator file saying
   `VERDICT: REAL_APP_BUG`: `QC_FAIL_VERDICT=<file> tools/qc-submit.sh $R <test> <step id> fail <file> --config`.
8. A NOW line at least every `loop.now_line_minutes` (`tools/log.sh $R NOW "step 7 (stop node2 and check the takeover): settle 120 of
   300 s; next: cluster-stopnode node2"`). Keep RESUME.md current (last submitted step, held step, exact next action, restart command).
9. All steps answered: `tools/qc-complete.sh $R <test> complete` (or the platform ended it: `autoEnded`). Compare the submitted ids
   with the sheet. `tools/log.sh $R DONE "..."`.

## Rules that apply
- Submit each step once, as soon as it is done, never batched; one try; on a STOPPED-SUBMIT line stop and tell the supervisor (no
  retry, resubmit or delete).
- FAIL only with the validator's REAL_APP_BUG verdict. Guard refusals, tool or environment limits, sheet IP / Windows / physical
  differences are never a FAIL: change the sequence, tweak the step to test the same thing and say so, or hold it.
- Answer your own questions with the most sensible choice (the one that tests what the step is about, keeps the cluster safe and is
  easy to undo), write the question and the answer into the comment or the DONE line.
- Every tool you write or change for this skill goes into `tools/` with a usage header (and the skill repo), never into the
  product repos.
- Tool problem or hung pool, with evidence logged in `run.log` (failing command and output, SUSPENDED, `txg_sync` in D state, `zpool
  list` rc 124): ask the supervisor for the reboot (`docs/safety.md` 5; no engine restart, no `sync`), then resume; the step is not failed.

## Forbidden
Bare `node-stop` of a cluster node; host `iscsiadm`; manual iSCSI logouts with a pool imported; `zpool export|clear` of a
SUSPENDED pool; recreating a working node; a host reboot without the supervisor's approval, a docker engine restart, `sync`; tokens or passwords in comments;
committing state/ files.

## Hand-back
The DONE line: test id and name, iteration, round dir, build tag, PASS ids, FAIL ids with reason and verdict file, held steps,
`zpool list` state, deviations from the sheet, tool changes. Then stop.

## Context limit
If the supervisor says you are above `loop.context_limit_agent`, finish the current test/step, write RESUME.md (next test, iteration, open items) and end.
