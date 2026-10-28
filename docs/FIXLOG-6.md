# Fix log, validation pass 6 (FEEDBACK-6.md)

All 13 findings were re-checked against the code; none was disputed. Selftest: 81 passed, 0 failed (was 58 before this pass). Secret scan clean. `bash -n` clean on all scripts.

| Id | Result | Fix |
|----|--------|-----|
| K-01 (major) | fixed | repl-iscsi-cross.sh: if the holder already has a session to the target IQN, it requires the holder to answer `zpool list` and to have no pool imported; otherwise REFUSED, rc 5, before any logout/ACL delete. docs/safety.md lists every logout path and its guard. Selftest: 3 cases (session+pool refused, no session allowed, session without pool allowed). |
| K-02 | fixed | qc-submit.sh reads `GET test-results/<T>/next` and stops (rc 3) if its step id differs from the one submitted. Assumption: the reply carries the id in one of `id`, `step_id`, `step.id`, `nextStep.id`, `next.id`. An unreadable reply only writes a NOTE; the ledger and history check still apply. |
| K-03 | fixed | A reply without the result: a JSON error means rejected (rc 1); otherwise wait 20 s and re-check history; a new row is stored (NOTE), no new row is stop 2 UNKNOWN. |
| K-04 | fixed | cluster-reset/build-repl create the state dirs, take the build lock (QC_BUILD_LOCKED lets build-repl's child reset pass) and refuse an unfinished `build<N>/status` unless QC_BUILD_RESTART=1 (or DRYRUN). Selftest: unfinished status refused and untouched, held lock refused. |
| K-05 | fixed | cluster-settle: whole-number `--settle`, unknown option refused; cfg.py validate rejects a non-integer settle_seconds and warns below 300. Selftest cases. |
| K-06 | fixed | ts-disk-remove: every running node must answer `zpool list`; exact `/dev/<L>` match on `zpool status -P`; dies if the disk is in use or no node runs. |
| K-07 | fixed | iscsi-stale-clean: "current" names built from all configured nodes; refuses if a name cannot be found. |
| K-08 | fixed | git-newbranch: dies if a local branch of that name exists and differs from `qc/<base>`. |
| K-09 | fixed | cluster-join: timeout or empty reply is logged JOIN UNKNOWN and followed by a reboot wait; never blindly resent. |
| K-10 | fixed | Unknown options refused (stopnode, reset, build-repl, settle); qc-complete exits 1 on non-2xx; qc-dltest refuses a reply without steps; refreshcversion fails if any node fails. Selftest cases incl. a local fake platform. |
| K-11 | fixed | supervisor-snapshot probes the pool on the first running node of every cluster. |
| K-12 | fixed | cluster-return stops its sampler through an EXIT trap. |
| K-13 | fixed | `valid_branch` in lib/common.sh used by git-newbranch, git-pushbranch, git-pr and both code-deploy entry points. Selftest: bad names refused. |
