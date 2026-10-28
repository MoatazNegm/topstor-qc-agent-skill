# FIXLOG-3 (answers FEEDBACK-3)

| id | result | what was done |
|---|---|---|
| H-01 | fixed | The committed bytecode file `tools/lib/__pycache__/cfg.cpython-39.pyc` is removed from the index (`git rm`, no history rewrite). `.gitignore` now has `__pycache__/` and `*.pyc`. `PYTHONDONTWRITEBYTECODE=1` is exported in `tools/lib/common.sh`, `tools/preflight.sh` and `tests/selftest.sh`, so running the tools or the selftest writes no bytecode. A selftest check asserts that no `__pycache__` exists in the tree. |
| H-02 | fixed | `ts-disk-add.sh` refuses a `--wait` value that is not a whole number (message, rc 1) before doing anything. Selftest case added (`--wait 5m`). |
| H-03 | fixed | `tools/README.md` lists `code-deploy.sh --check-branch <BRANCH> [cluster]` with its exit codes (0 present, 1 MISSING, 2 not reachable) and `deploy.software_repo_check_from`, and `ts-disk-add.sh <count> [GB] [--wait <s>]`. `docs/safety.md` section 3 names `--wait`. `docs/loop-rules.md` says the reset also refuses when the repo cannot be reached (rc 2: fix the URL or set `deploy.software_repo_check_from`). |

No finding disputed. Checks: `tests/selftest.sh`, `bash -n` on all scripts, `tools/secret-scan.sh`.
