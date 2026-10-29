# FIXLOG-12 (v1.1.4, from FEEDBACK-v113.md)
| id | result | what changed |
|---|---|---|
| W-01 | fixed (claim re-checked: no `0A` in any role file) | `docs/roles/supervisor.md` prompt template now includes `SKILL.md` section 0A; Inputs of tester, coder and validator name `SKILL.md` section 0A. Selftest checks all four. |
| W-02 | fixed (claim re-checked: order differed) | `docs/integrity.md` rules reordered to match SKILL.md 0A: 5 FINAL, 6 platform unchangeable, 7 MODIFIED stop. |
| W-03 | fixed (claim re-checked: empty hash gave `manifest  MODIFIED`) | `tools/qc-submit.sh`: `MH=${MH:-none}`; selftest checks `manifest (none\|<12 hex>) MODIFIED` for the empty-status case. |
VERSION 1.1.3 -> 1.1.4, manifest updated with `tools/verify-manifest.sh --update`.
