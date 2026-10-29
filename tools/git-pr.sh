#!/bin/bash
# git-pr.sh <BRANCH> [--title <t>] [--body-file <f>]   PREPARE the final pull-request REQUEST for the maintainer: ALL THREE repos (TopStor, pace,
# topstorweb), written to state/pr-request-<BRANCH>.md (branch, head commit, upstream target, loop state). Refused unless loop-state.sh
# is-clean says one full iteration passed with no code change since the last fix. It does NOT open any pull request: PRs to the maintainer's
# moataznegm repos are opened only by the maintainer (test users have no write token; docs/integrity.md).
. "$(dirname "$(readlink -f "$0")")/lib/git.sh"
BR=${1:?branch}; shift
valid_branch "$BR" || die "bad branch name '$BR' (letters, digits, . _ / - only)"
TITLE="TopStor QC: $BR (one full QualityCheck iteration passed with no code change)"; BODY=
while [ $# -gt 0 ]; do case $1 in --title) TITLE=$2; shift;; --body-file) BODY=$2; shift;; esac; shift; done
"$QC_TOOLS/loop-state.sh" is-clean || die "no clean full iteration yet: pull requests are opened only after one"
OWN=$(cfg get repos.user_owner); BASE=$(cfg get repos.upstream.base_branch)
RQ=$QC_STATE/pr-request-$BR.md
{ echo "# Pull-request request for $BR ($(date -u +%FT%TZ))"; echo; echo "skill v$(cat "$QC_ROOT/VERSION" 2>/dev/null) manifest $("$QC_TOOLS/verify-manifest.sh" --hash | cut -c1-12) $("$QC_TOOLS/verify-manifest.sh" --status)"; echo
  [ -n "$BODY" ] && [ -r "$BODY" ] && { echo "Title: $TITLE"; echo; cat "$BODY"; echo; }
  for r in $REPOS; do echo "- $r: $(repo_url "$r") branch $BR head $(gls --heads "$(repo_url "$r")" "$BR" | cut -c1-12) -> upstream $(repo_upstream "$r") base $BASE"; done
  echo; echo "Loop state: $("$QC_TOOLS/loop-state.sh" show)"; } > "$RQ"
echo "PR REQUEST written: $RQ -- give it to the maintainer; this tool does not open pull requests."
