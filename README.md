# topstor-qc-agent-skill

A portable agent skill that runs the TopStor **QualityCheck** test loop on your own TopStor nodes: containers on one docker host,
physical servers, or VirtualBox VMs. It works with any LLM agent that can run a shell and make HTTP calls; `SKILL.md` is the prompt.

What it does: follows the platform's tests step by step with your tester key, submits every step once with evidence, holds any
step it cannot pass for an independent validator, fixes real app bugs in your TopStor / pace / topstorweb repos on a new branch,
proves the whole test locally, pushes the branch, returns to the platform, and after one full iteration with no code change opens
pull requests to the upstream `moataznegm` repos for all three.

## Quick start

1. Requirements on the agent machine: `bash`, `curl`, `python3` (no extra modules), `git`, `zip`/`unzip`, plus `docker` (container
   nodes), `ssh`/`scp` (physical and VirtualBox nodes) and `VBoxManage` (VirtualBox, local or via `vbox_manager_ssh`).
   Container flavour: run the agent on the docker host of the node containers (the host tools touch its kernel's LIO/loops).
2. Put every secret in its own file, first line only, `chmod 600`, outside any git repo: the platform tester key, the TopStor admin
   password(s), a git "store" credential file with your GitHub token, optional ssh keys.
3. `cp config/input.example.yaml config/input.yaml` and fill in every `CHANGE_ME`: nodes (name, type, address, container / ssh user /
   VM name, role, cluster), platform URL and app id, the key and password FILE paths, your three repos and clones, the upstream repos
   and base branch, the `deploy:` section (push command and node software repo URL: how a fix reaches the nodes) and, for the container
   flavour, `container_host:` (the disk regexes name files the tools WIPE). `config/input.yaml` is git-ignored.
4. `tools/preflight.sh` until it prints `PREFLIGHT OK` (rc 2 = the config is missing or incomplete; it names the fields).
5. `tests/selftest.sh` (offline check of the tools; touches nothing).
6. Start your agent as the SUPERVISOR with `SKILL.md` and `docs/roles/supervisor.md`. It starts fresh agents for each test
   (tester), each held step (validator) and each fix (coder) and reports to you every 3 minutes.

## Layout

| Path | What |
|---|---|
| `SKILL.md` | the prompt: roles (supervisor, tester, validator, coder), the loop rules, safety summary |
| `config/input.example.yaml` | every input the agent needs (secrets as file paths only) |
| `tools/` | node wrappers, cluster tools, platform tools, git/PR tools, reports, supervisor tools (`tools/README.md`) |
| `docs/loop-rules.md` | the loop in detail: submission, stop and hold rules, FAIL, iterations, clean count, branches |
| `docs/safety.md` | cluster safety rules: settle, stop, iSCSI, pools, disks, builds, reboots |
| `docs/platform-api.md` | the QualityCheck endpoints the loop uses, headers, checks after each submit |
| `docs/integrity.md` | VERSION, manifest, stamp, what the platform must enforce |
| `docs/quiet-tools.md` | low-output wrappers for agents |
| `docs/pitfalls.md` | lessons from earlier runs |
| `docs/node-types.md` | the node abstraction, how to add a type, what is flavour-specific |
| `docs/roles/*.md` | one brief per role (goal, inputs, steps, rules, forbidden, hand-back); the supervisor brief holds the report spec |
| `tests/selftest.sh` | offline self-test |
| `state/` | created at run time: rounds, ledgers, timings, agents, mailbox (git-ignored) |

## Integrity (audit aid, NOT enforcement)

`VERSION`, `MANIFEST.sha256` and `tools/verify-manifest.sh` let anyone see whether the skill files were changed. `tools/qc-submit.sh`
stamps every step comment with `skill vX.Y.Z manifest <12 hex> OK|MODIFIED`. This is an AUDIT aid: it cannot technically stop a
determined user, who can edit the checker too. Real enforcement is server side: the platform allow-lists accepted manifest hashes
and rejects or flags others; pull requests to the maintainer's `moataznegm` repos are opened only by the maintainer (test users have no
write token); merge eligibility (one full iteration on the same app version with zero code changes) is computed by the platform.
The agent rules that must not be changed are in `SKILL.md` section 0A. Details: `docs/integrity.md`.

## Limits

- The container-flavour host tools assume the TopStor dev layout (node containers with a nested docker, `/root/loopdisks` export
  lists, loop-file test disks); adjust `container_host.*` in the config to your paths.
- Physical servers cannot be powered on remotely without an out-of-band command (`start_command`, e.g. IPMI with a password file);
  without one the agent asks you to power the server on and waits. Disk add/remove steps on physical servers need real disks or
  your hypervisor; the agent asks when it cannot do them.
- `cluster-reset.sh` and `cluster-join.sh` drive the product's own `docker_setup.sh reset`, `hosts/config` and `hosts/joincluster`
  calls; if your TopStor version changes those, adapt the two tools.
- The agent framework itself (how a "fresh agent" is started, how often the supervisor wakes up) is yours: the skill only needs a
  shell, HTTP and a way to start agents with an empty history.
