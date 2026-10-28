# FIXLOG-8

| id | status | what |
|---|---|---|
| M-01 | fixed | Claim re-checked (the tool refuses when a configured node is not running). `tools/iscsi-stale-clean.sh` header (line 4) and the refusal message now say: use it only when every configured node is up and no pool is imported (e.g. right after a `--no-disks` build); at the build start (nodes stopped) use `host-stale-clean.sh`. Docs grep: no other file uses the "between builds / at the build start" wording for this tool. |
