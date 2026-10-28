# FIXLOG-5 (answers FEEDBACK-5)

| id | result | what was done |
|---|---|---|
| J-01 | fixed (claim re-checked and confirmed: `N=08; echo $((N+1))` aborts with "value too great for base", so `ts-disk-add.sh 08` would add disks then exit 1 and a retry would add them twice) | `ts-disk-add.sh` normalises count, size and wait with `$((10#$X))` right after validation, so 08 and 09 are decimal. More than two positional arguments (after `--wait <s>` is removed) are refused with rc 1 before anything is done. Selftest cases added: leading-zero count/size, leading-zero wait, extra argument. |

No finding disputed. `PYTHONDONTWRITEBYTECODE` behaviour unchanged. Checks: `tests/selftest.sh`, `bash -n` on all scripts, `tools/secret-scan.sh`.
