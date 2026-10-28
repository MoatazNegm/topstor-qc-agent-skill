#!/bin/bash
# git-latest-branch.sh   the version under test: the highest <branch_prefix><N> branch (no suffix) on YOUR three repos; prints one
# line per repo and "LATEST <branch>" when all three agree (rc 0), else "MISMATCH" (rc 1: tell the user which repo is behind).
. "$(dirname "$(readlink -f "$0")")/lib/git.sh"
all=""; for r in $REPOS; do b=$(latest_branch "$(repo_url "$r")"); echo "$r: ${b:-none}"; all="$all ${b:-none}"; done
u=$(echo $all | tr ' ' '\n' | sort -u); [ "$(echo "$u" | wc -l)" = 1 ] && [ "$u" != none ] && { echo "LATEST $u"; exit 0; }
echo "MISMATCH:$all"; exit 1
