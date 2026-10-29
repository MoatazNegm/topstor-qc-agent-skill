# FIXLOG-11 (v1.1.3, from FEEDBACK-v112)

All five claims re-checked against the files and confirmed.

| id | result |
|---|---|
| V-01 | fixed: wording removed in tools/verify-manifest.sh:6, README.md:37, SKILL.md 0A heading, docs/integrity.md:15; selftest greps tracked files (FIXLOGs excluded) for "server side" / "must enforce" |
| V-02 | fixed: explicit rule "the test platform cannot be changed" as SKILL.md 0A.6 and docs/integrity.md rule 7 |
| V-03 | fixed: duplicate FINAL bullet at the end of docs/loop-rules.md section 7 removed (rule stays in section 3) |
| V-04 | fixed: rc 9 message quoting corrected; stamp uses ${MS:-MODIFIED}; selftest for ACK with empty status |
| V-05 | fixed: stale GitHub API clause removed from tools/lib/git.sh header |
