# Integrity layer (AUDIT aid, not enforcement)

## What it is
- `VERSION`: the skill version (`X.Y.Z`).
- `MANIFEST.sha256`: sha256 of the major files: `SKILL.md`, `README.md`, `VERSION`, all `docs/*.md` and `docs/roles/*.md` (not the
  FIXLOGs), everything under `tools/` (submit/step scripts, node wrappers, cluster tools, libs), `config/input.example.yaml`,
  `tests/selftest.sh`. Not listed: your `config/input.yaml`, `state/`.
- `tools/verify-manifest.sh`: recomputes the hashes. Prints `OK` or `MODIFIED` plus the changed, missing or unlisted files (rc 0 / 1).
  `--status` prints one word, `--hash` prints the manifest hash.
- `tools/qc-submit.sh` (the only way to submit a step) ends EVERY step comment with
  `[skill vX.Y.Z manifest <first 12 hex of the manifest hash> OK|MODIFIED]` and repeats it in the STEPCHECK line. `MODIFIED` = at least
  one listed file differs from the manifest (or the manifest is missing).

## What it is NOT
This is an **audit aid**. It lets the maintainer see, in the step comments, which skill build produced a result, and it flags casual or
accidental edits. It **cannot technically stop a determined user**: whoever can edit the rules can edit `verify-manifest.sh`,
`qc-submit.sh` or the manifest as well, or post to the platform without the wrapper. Do not rely on it for trust.

## What protects the maintainer's repos (nothing is checked on the platform)
1. Pull requests to the maintainer's `moataznegm` app repos are opened ONLY by the maintainer. Test users have no write token for
   those repos. `tools/git-pr.sh` only writes the request file for the maintainer; it is not a way around this.
2. Merge eligibility is checked by the maintainer, not claimed by the user: one FULL iteration on the SAME app version (same branch and
   commits of TopStor, pace, topstorweb) with ZERO code changes, with every step stored once, read from `state/loop.json` and the
   platform history. The stamp (`OK|MODIFIED`, hash) in the step comments is what the maintainer reads as audit evidence.
3. The skill (this repo) is released only by the maintainer: `verify-manifest.sh --update` is run after a reviewed change.

## Non-changeable rules for the agent (also in SKILL.md section 0A)
1. Do not start extra subagents beyond the ones the skill and the supervisor's brief name (one fresh agent per task, one role brief each).
2. Do not edit the rules, the role briefs, `VERSION`, `MANIFEST.sha256` or any file the manifest lists; never run
   `verify-manifest.sh --update`. If a rule seems wrong or a tool is faulty, hold the step and tell the user (the maintainer changes the tool and runs `--update`; a local fix is allowed only if the user says holding blocks the loop, and the stamp then reads MODIFIED until a reviewed release).
3. Submit one step at a time, only through `tools/qc-submit.sh`, once. Never call the platform's submit endpoint by hand.
4. Never open pull requests (or push) to any `moataznegm` repository. Push only to the user's own repos.
5. If `verify-manifest.sh` says `MODIFIED` and you did not intend it, stop and tell the user before submitting anything.
6. A submitted step is FINAL: never re-checked, replaced, deleted or resubmitted; never propose it or ask the user to allow it. Judge carefully before the one submit; later corrections go into the next iteration only.
7. The test platform cannot be changed: never design, request or propose platform-side changes (allow-lists, new fields, server gates); integrity is an audit stamp only. Work only with the existing endpoints in `docs/platform-api.md`.
