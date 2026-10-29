# New-user setup (the agent follows this after cloning the skill)

You are the agent of a NEW user. Do these steps in order, with the user. Never print, copy, log or commit a key, password or token.

## What the maintainer must give the user first
- Read access to the private repo `MoatazNegm/topstor-qc-agent-skill` (a GitHub read token).
- A platform tester key (for https://quality-check-omega.vercel.app, app id 10).
Without both, stop and tell the user to ask the maintainer.

## 1. Requirements
Check `bash`, `curl`, `python3`, `git`, `zip`, `unzip`; plus `docker` (container nodes), `ssh`/`scp` (physical / VirtualBox nodes),
`VBoxManage` (VirtualBox). Tell the user what is missing; do not continue until the needed ones exist.
Container nodes: run on the docker host of the node containers (the tools touch its LIO/loop devices); otherwise stop and tell the user.

## 2. Verify the skill
`cd` into the skill root, `cat VERSION`, `tools/verify-manifest.sh`. It must print `OK`; otherwise STOP and tell the user.

## 3. Secrets
Each secret in its own file: first line only, `chmod 600`, outside any git repo: the tester key, the TopStor admin password(s), the
git token. Ask the user for the paths (create nothing with a guessed value).
The git credential file holds ONE line `https://<github-user>:<token>@github.com`. A bare token file does not work: stop and ask the
user to convert it (never echo it); with the user's consent only: `{ printf 'https://%s' <github-user>; printf ':%s@github.com\n' "$(head -1 <tokenfile>)"; } > <PATH>; chmod 600 <PATH>`.
If git answers `Invalid username or token` although the token is correct, the file format is wrong. Clone with:
`git -c credential.helper='store --file=<PATH>' clone https://github.com/MoatazNegm/topstor-qc-agent-skill.git ~/topstor-qc/skill`
`repos.credential_file` (config) must hold a token that can PUSH to the user's own TopStor, pace and topstorweb repos (it may be the same
file if that token also reads the skill repo).

## 4. Config
`cp config/input.example.yaml config/input.yaml`, then fill EVERY `CHANGE_ME` together with the user and replace every example path
(secret files, credential file, clone dirs) with the user's answer; never keep an example path. First ask each node's type
(container / physical / virtualbox), its IP and address, and use the matching example block. Then: platform URL
`https://quality-check-omega.vercel.app/api` (keep `/api`) and app id `10`; the secret file paths; the three repos TopStor / pace / topstorweb and their
clones; upstream repos and base branch; the `deploy:` section; and, for container nodes only, `container_host:` (its disk regexes name files the tools WIPE:
confirm each with the user before saving). Never guess a value: ask.

## 5. Checks
`tools/preflight.sh` until `PREFLIGHT OK` (rc 2 = config incomplete; it names the fields). `tests/selftest.sh` must report 0 failed.

## 6. Run as SUPERVISOR
Read `SKILL.md` section 0A and `docs/roles/supervisor.md`. Start a fresh agent per test (tester), per held step (validator) and per
fix (coder). Report to the user every 3 minutes as in `docs/roles/supervisor.md` section 1: clock time, every agent's status, test and step in words,
iterations left, tests passed in a row with no code change, and what waits for the user.

## Standing rules (short)
- A submitted step is FINAL: never re-check, replace or resubmit it.
- The platform cannot be changed; work with the existing endpoints only.
- `verify-manifest.sh` says MODIFIED and nobody intended it: stop and tell the user. The stamp is an audit aid only; nothing on the platform checks it.
- FAIL only for real app bugs, never for tool, environment or guard problems (hold the step instead).
- No `sync`, no docker daemon restart, no storage code.
- An empty reply to a submit means STOP: check the step history before anything else.
