# FIXLOG-14 (v1.2.0)
User order: move the new-user setup prompt into the skill.
- Added docs/SETUP.md (requirements, manifest check, secrets, config, preflight/selftest, supervisor start, standing rules, what the maintainer must give the user).
- README: new top section "New user: paste this" with the one-line prompt; SETUP.md in the layout table.
- SKILL.md: one line before section 0 pointing to docs/SETUP.md (it is listed in the manifest via docs/*.md).
- VERSION 1.2.0, MANIFEST.sha256 regenerated. No-server-side-enforcement wording kept.
