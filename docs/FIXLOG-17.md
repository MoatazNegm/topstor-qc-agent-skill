# FIXLOG 17 (v1.2.2 -> v1.2.3, feedback FEEDBACK-v122)
- U-01 fixed: the bare-token conversion in docs/SETUP.md now runs in a subshell with `umask 077`, so the credential file is private from the moment it is created; `chmod 600` stays as a second guard. Two selftest checks: SETUP contains the umask form, and the command creates mode 600 even under umask 022.
Selftest all green, verify-manifest OK, secret scan clean.
