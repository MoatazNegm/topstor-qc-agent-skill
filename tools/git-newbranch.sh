#!/bin/bash
# git-newbranch.sh <NEW BRANCH> [base branch]   start a fix branch in all three clones FROM THE LATEST PUSHED BRANCH (default: the
# result of git-latest-branch.sh). Never edits a branch that is already pushed (refuses when NEW BRANCH exists on your remote).
# Clones that do not exist yet are cloned from your repo URL. A branch made from an older base once silently lost a fix: the
# script proves the base head is an ancestor of the new branch.
. "$(dirname "$(readlink -f "$0")")/lib/git.sh"
NB=${1:?new branch}; BASE=$2
valid_branch "$NB" || die "bad branch name '$NB' (letters, digits, . _ / - only)"
[ -n "$BASE" ] || BASE=$("$QC_TOOLS/git-latest-branch.sh" | sed -n 's/^LATEST //p'); [ -n "$BASE" ] || die "no common latest branch; give the base explicitly"
for r in $REPOS; do d=$(repo_clone "$r"); u=$(repo_url "$r")
	[ -d "$d/.git" ] || { mkdir -p "$(dirname "$d")"; GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c "credential.helper=store --file=$CRED" clone -q "$u" "$d" || die "clone of $r failed"; }
	[ -z "$(g "$r" status --porcelain)" ] || die "$r: working tree not clean ($d); commit or stash first"
	gls --heads "$u" "$NB" | grep -q . && die "$r: branch $NB already exists on your remote (never edit a pushed branch; take the next number)"
	g "$r" fetch -q "$u" "+refs/heads/$BASE:refs/remotes/qc/$BASE" || die "$r: fetch of $BASE failed"
	# K-08: an existing LOCAL branch of that name is never reset (its unpushed commits would survive only in the reflog)
	if g "$r" rev-parse -q --verify "refs/heads/$NB" >/dev/null && [ "$(g "$r" rev-parse "refs/heads/$NB")" != "$(g "$r" rev-parse "refs/remotes/qc/$BASE")" ]; then
		die "$r: local branch $NB already exists and differs from $BASE (unpushed work?): push or rename it, or take the next number"; fi
	g "$r" checkout -q -B "$NB" "refs/remotes/qc/$BASE" || die "$r: checkout failed"
	g "$r" merge-base --is-ancestor "refs/remotes/qc/$BASE" HEAD && echo "$r: $NB from $BASE $(g "$r" rev-parse --short HEAD)" || die "$r: base not an ancestor"
done
