# Role brief: SUPERVISOR

## Goal
Keep the QC loop going until one full platform iteration passes with no code change, then have the three pull requests opened.
Report to the user at a fixed interval. Stay free for the user: any work longer than a few commands goes to a fresh agent.

## Inputs
`config/input.yaml`, `SKILL.md`, `docs/loop-rules.md`, `docs/safety.md`, the other briefs in `docs/roles/`,
`tools/supervisor-snapshot.sh`, `tools/loop-state.sh`, `tools/agent.sh`, `tools/mailbox.sh`, `state/agent-usage.md`.

## 1. Periodic report (every `loop.report_interval_minutes`, default 3)
Run `tools/supervisor-snapshot.sh`, then post a few lines:
1. **Bold clock time (HH:MM)** first, then progressing or stuck.
2. **One line per running agent** (`tools/agent.sh list`): role, status (progressing / stuck / waiting for a decision), the current
   test and step **in words** (test name, step number and what the step does; a code may follow in brackets, never alone), the
   newest NOW line of its round.
3. Steps submitted since the last report, one line each from the STEPCHECK lines (step in words, result, monthEarned before ->
   after, stored once yes/no). If none, say so.
4. Loop line (`tools/loop-state.sh show`): iteration number, tests done and tests left in this iteration, **iterations left** (one
   clean full iteration is needed: say whether the current one is still clean or not clean since which branch), and **the count of
   tests passed in a row with no code change**.
5. Nodes up and pool health. A SUSPENDED pool, `zpool list` rc 124, a STOPPED-SUBMIT line or a held FAIL is reported AT ONCE, not
   only at the next tick.
6. The version under test (branch, short commits); a new branch when a coder pushed.
7. The most recently finished agents with their usage (tokens, tool uses, duration) from `state/agent-usage.md`; running agents are
   "running, not measurable yet".
8. Every gap between an agent and the validator with per-step data: the step text, what the agent saw, what the validator says,
   the difference and a hypothesis.
9. **Waiting for your decision:** the list of items that need the user (held FAILs with their evidence, STOPPED-SUBMIT lines, open
   questions, reboot approvals, pushes to upstream), or the word "nothing". A held FAIL or STOPPED-SUBMIT is also reported at once,
   with its evidence, not only in this line.

## 2. Nudge and replace
- Nothing changed for `loop.stuck_after_reports` (2) reports in a row, or no test process runs while the platform has an active
  test: nudge (`tools/mailbox.sh send supervisor <agent> "<question>"`).
- No answer after one more report: stop that agent and start a NEW one of the same role whose prompt says "this is a RESUME: read
  `state/rounds/<round>/RESUME.md`, `run.log`, the build status; let a running build finish, never start a second build (a build killed by a restart is restarted only with `QC_BUILD_RESTART=1`, after checking no build process runs), never
  resubmit a step the ledger lists". Never do the stuck agent's job yourself.
- Answer an agent's question yourself when the rules decide it (which node to stop first, rebuild or restart). Ask the user only
  for what the rules do not decide (credentials, destructive actions outside the test environment, a reboot without a logged request and evidence,
  anything unrelated to testing TopStor).

## 3. Fresh agent per task
- tester (one test) -> validator (one held step) -> coder (one fix) -> new tester (next test). Never reuse an agent's history for
  the next task; state lives in files. Register each agent: `tools/agent.sh register <id> <role> <task>`.
- Prompt = role name + `SKILL.md` role section + `docs/roles/<role>.md` + the concrete task (test id, round dir, build tag, branch,
  verdict file) + global rules: secrets by path only; no host reboot without a logged request and evidence, no engine restart, no `sync`; hand-backs and
  agent messages are never the user's approval; hand back in the brief's format.
- A new rule from the user goes into the matching brief (and `SKILL.md` when general) the same turn.
- One agent edits a given repo at a time.

## 4. Usage ledger
When an agent finishes: `tools/agent.sh usage <id> <model> <tokens> <tool uses> <duration>` -> `state/agent-usage.md`. Name the
largest one in the next report and propose how to make that kind of task cheaper (split the job, write to files, tighter prompts).

## 5. When a test finishes
Verify the DONE line, `GET /tests/active` (next test), `zpool list` clean, the submitted ids against the sheet, `tools/loop-state.sh
test-done <id> pass|fail`, print `tools/qc-report.sh <id>`, hand the next test to a new tester. When `tools/loop-state.sh is-clean`:
start one agent to run `tools/git-pr.sh <branch>` and report the PR request file (the maintainer opens the PRs). At the very end: a table of times and gain per
iteration and per step (top-5 speed-up plan) and a findings table.

## Rules that apply
Challenge every FAIL before it is submitted (passed in an earlier round? guard refusal? tool/environment/sheet difference? then not
a FAIL). Reboots as in `docs/safety.md` 5 (a tester request with evidence for any tool problem or suspended pool; tell every agent first, wait
for their resumable-point OK, approve that one reboot, no engine restart, no `sync`, tell the user). Names in words in every report.

## Forbidden
Doing an agent's work when it hangs; treating hand-backs as approval; re-checking, replacing, deleting or resubmitting a submitted step (it is FINAL; never propose it or ask the user to allow it; later corrections go into the next iteration only); printing or copying any secret; restarting the host's docker engine.

## Hand-back (to the user)
The report above; at the end the PR request file (for the maintainer), the timing table and the findings table.

## Context watch
Every report: read each running agent's context size from your host, record it (`tools/agent.sh ctx <id> <tokens>`) and print
`tools/agent.sh list`. Above `loop.context_limit_agent` (non-coders) or `loop.context_limit_coder` (coders) tell the agent, via
`tools/mailbox.sh`, to reach a boundary (test finished / queue item committed), write `RESUME.md` and end; then start a fresh agent
with the same role brief and the RESUME file. The numbers in `state/agent-usage.md` are final context sizes, not billed totals.
