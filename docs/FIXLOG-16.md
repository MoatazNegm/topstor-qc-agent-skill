# FIXLOG 16 (v1.2.1 -> v1.2.2, feedback FEEDBACK-v121)
- T-01 fixed: README and SETUP write the credential line normally (`https://<github-user>:<token>@github.com`). `tools/secret-scan.sh` exempts only the pure placeholder form `<..>:<..>@`; `bob:abc123@` and `<u>:realtok@` are still flagged (3 selftest cases). SETUP says `Invalid username or token` with a correct token means a wrong file format, and gives a no-echo conversion command for a bare token file, only with the user's consent.
- T-02 fixed: README Quick start points to docs/SETUP.md as the single setup path. `tools/preflight.sh` prints `PREFLIGHT WARN` when a `*_file`/`*dir`/`clone` value still equals an example path (2 selftest cases).
Selftest all green, verify-manifest OK, secret scan clean.
