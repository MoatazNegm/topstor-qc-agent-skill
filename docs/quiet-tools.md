# Quiet tooling (output discipline)

An agent's context is its main cost: every line a tool prints stays there. These tools keep output to one line and put the rest in
files under `state/`. They change no rule (submit once, FAIL only for a real app bug, keys by path only).

| Tool | Use |
|---|---|
| `tools/qc-submit.sh <round> <test> <step> <pass\|fail> <comment-file> [--config]` | judge first, then submit ONE step; ledger refuses a resend; does the STEPCHECK (monthEarned before -> after, history row stored once) into `run.log`; rc != 0 means STOP (see `docs/loop-rules.md` 3) |
| `tools/qc-dltest.sh <id>` / `tools/round-new.sh` | download the test and steps once into `state/tests/`; read the steps file once, then work from it |
| `tools/qtail.sh <label> -- <cmd...>` | run a noisy command (build, reset, join, `zpool`, etcd or status dumps): success prints the last 5 lines, failure the last 20, full output in `state/quiet/<label>.out`, secrets masked |
| `tools/qlog.sh <file> [n]` | line count, error/fail count and the last n lines of a log |
| `tools/qcheck.sh [node]` | pool health (all ONLINE, timeout 10 s), isinsync, active platform test and git status in ONE line; odd items expanded, rc 1 (`QCHECK_DRY=1` dry run) |

Open a full log only with `grep` or `tail -n 20` on the exact lines you need. Keep tool turns small and long jobs in the background
with their own log.
