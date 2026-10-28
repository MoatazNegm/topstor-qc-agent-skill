# FIXLOG-4 (answers FEEDBACK-4)

| id | result | what was done |
|---|---|---|
| I-01 | fixed (claim re-checked and confirmed: `ts-disk-add.sh 1 --wait` took `--wait` as the size, `truncate` failed and the loop continued) | `ts-disk-add.sh` now refuses, with rc 1 before anything is done: a count or size that is not a whole number or is below 1, and a trailing `--wait` with no value. The backing file, the free loop node, the `losetup` attach and the device node are each checked; on any failure the script stops with an error (rc non-zero), removes a half-made backing file, and nothing is appended to the export lists (`container_host.loopdisks_files`) until the loop device exists as a block device. Selftest cases added: bad counts (`x`, `1.5`, `0`, `-1`), bad size (`2.5G`), trailing `--wait`, and a valid dry run. |

No finding disputed. `PYTHONDONTWRITEBYTECODE` behaviour unchanged. Checks: `tests/selftest.sh`, `bash -n` on all scripts, `tools/secret-scan.sh`.
