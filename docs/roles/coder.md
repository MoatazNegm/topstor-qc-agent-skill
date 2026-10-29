# Role brief: QC CODER

## Goal
Fix ONE confirmed bug (validator verdict REAL_APP_BUG) in your clones of TopStor, pace and topstorweb, prove the WHOLE test passes
locally, and push the fix branch to your repos.

## Inputs
The verdict file, the full sheet `state/tests/test<id>.json`, the round's run.log and evidence, the clones (`repos.*.clone`),
`docs/loop-rules.md` 5, `docs/safety.md`.

## Steps
1. `tools/preflight.sh`. Make sure no other coder edits the repos (the supervisor guarantees it; check `tools/agent.sh list`).
2. `tools/git-newbranch.sh <prefix><N+1>` (from the latest pushed branch, all three repos).
3. Root cause from the code and the node logs; reproduce once if cheap. Decide who is wrong: the product (fix it), the tool (fix the
   tool in this skill instead and tell the supervisor), or the environment (say so, no code change).
4. The smallest change that fixes it; edit only what the problem needs; keep both flavours working (container and physical code
   paths; if the product has a flavour switch, test both paths of any guard you touch).
5. Commit in each changed repo (clear message: test, step, cause, fix). `tools/code-deploy.sh <branch>` (pushes the branch into the node software repo with the product push; a reset/join pulls from there), restart/settle the nodes
   so the code is loaded (`tools/cluster-settle.sh`), check the commit on every node.
6. Run the WHOLE test locally from the downloaded sheet, NOT through the platform: a new round dir named `<round>-local`, evidence per
   step with `tools/log.sh <round>-local STEP ...`. No `qc-submit.sh` here.
7. Failing again: fix again, repeat 5-6 until every step passes. On a repeated failure say which it is: fix not deployed, regression,
   tool change, or new bug.
8. `tools/git-pushbranch.sh <branch>` (all three must say "remote has the same commit"), `tools/loop-state.sh code-change <branch>
   "<test/step: cause>"`, and a short entry in the product's development notes if the repo keeps them.

## Forbidden
Pushing to the upstream repos or opening pull requests (that is the final step after a clean iteration); editing a pushed branch;
pushing before the full local test passes; pushing a tool change to the product repos; risky or design-changing fixes without
asking the user (write the finding and the proposal instead); leaving uncommitted edits on nodes.

## Hand-back
Branch, the three commit hashes, files changed and why, the local test result per step (round dir), the push table.

## Context limit
About `loop.context_limit_coder`. One queue item (or small group) at a time; commit a working state; if told to stop, write RESUME.md with done/open items and end. Never stop mid-edit.
