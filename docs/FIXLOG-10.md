# FIXLOG-10 (v1.1.2, second validator pass)

- M-1 fixed: SKILL.md, README.md, docs/integrity.md no longer claim server-side enforcement (no platform allow-list, no platform-computed merge eligibility). The stamp is an audit aid read by the maintainer; protection rests on the maintainer-only rule (0A.4) and on test users having no write token; the maintainer checks merge eligibility from state/loop.json and the platform history. integrity.md items 1 and 4 dropped, item 3 recast; allow-list step removed from the release workflow.
- m-1 fixed: the FINAL rule appears once per place (SKILL.md 0A.5 and the supervisor Forbidden line).
- m-2 fixed: tools/qc-submit.sh stops with rc 9 unless the status is OK (empty counts as not OK), unless QC_ACK_MODIFIED=1; selftest for the empty-status case.
- m-3 fixed: unused gh_api and _gh_hdr removed from tools/lib/git.sh; selftest checks no tool references api.github.com.
- m-4 fixed: docs/roles/coder.md and docs/loop-rules.md wording.
- Release: verify-manifest.sh --update, VERSION 1.1.2.
