# FIXLOG-7 (feedback pass 7, L-01..L-06)

| id | result | what changed |
|---|---|---|
| L-01 | fixed | `ts-disk-remove.sh` sources `lib/tstor.sh` (`zpool_answers`, `pools_on`). Selftest: idle lab passes, hung zpool gives rc 3. |
| L-02 | fixed | Claim confirmed (loops are exported over LIO, `zpool status -P` shows by-id names, never `/dev/loopN`). The grep check is removed; the tool now refuses (rc 5) while ANY pool is imported on a running node, as the stale-loop clean-up does. Selftest: pool imported = rc 5. |
| L-03 | fixed | `qc-submit.sh` stops with rc 3 and sends nothing when `/next` says `allDone:true` / "No more steps". Selftest fake platform now returns the real shape `{"step":{"id",...},"test_id","test_name"}` (200) and the 404 allDone shape; `platform-api.md` documents both. |
| L-04 | fixed | Alias fallback removed. A configured node that is not running (name unreadable) = REFUSED; the name is per build. Selftest added. |
| L-05 | fixed | `QC_BUILD_RESTART=1` documented in `roles/tester.md` (RESUME), `roles/supervisor.md` (resume prompt) and `tools/README.md`. |
| L-06 | fixed | The HTTP code of the submit is captured (`-w`); a reply is a rejection (rc 1) only for a 4xx with a JSON `error`. A 200 with `message` and no `result` goes to the history re-check (match = OK with a NOTE, otherwise UNKNOWN rc 2). Selftest added. |

Checks: `bash -n` on all scripts clean; selftest 87 passed, 0 failed; secret scan CLEAN.
