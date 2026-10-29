# FIXLOG-15 (v1.2.1)
Validator FEEDBACK-v120 findings, all fixed (docs only, no tool changes).
- S-01 fixed: SETUP.md enforcement line reworded; selftest green.
- S-02 fixed: credential file format (one line `https:// <user> : <token> @github.com`, no spaces) in README prompt and SETUP step 3, exact `git -c credential.helper='store --file=<PATH>' clone` command, bare token file -> stop and ask.
- S-03 fixed: SETUP step 1 docker-host rule for container nodes.
- S-04 fixed: SETUP step 4 asks node type first; container_host only for container nodes.
- S-05 fixed: replace every example path, never keep one.
- S-06 fixed: repos.credential_file token must push to the user's three repos.
- S-07 fixed: SETUP step 6 points to supervisor.md section 1 with the full report items.
- S-08 fixed: platform URL written with /api.
Selftest 107/107, verify-manifest OK, secret scan clean.
