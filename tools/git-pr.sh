#!/bin/bash
# git-pr.sh <BRANCH> [--title <t>] [--body-file <f>]   open the FINAL pull requests from YOUR repos to the upstream repos (repos.upstream,
# base repos.upstream.base_branch) for ALL THREE: TopStor, pace, topstorweb. Refused unless loop-state.sh is-clean says one full
# iteration passed with no code change since the last fix (FORCE_PR is not offered). An existing PR for the same head is reported,
# not duplicated. Prints one PR URL per repo.
. "$(dirname "$(readlink -f "$0")")/lib/git.sh"
BR=${1:?branch}; shift
valid_branch "$BR" || die "bad branch name '$BR' (letters, digits, . _ / - only)"
TITLE="TopStor QC: $BR (one full QualityCheck iteration passed with no code change)"; BODY=
while [ $# -gt 0 ]; do case $1 in --title) TITLE=$2; shift;; --body-file) BODY=$2; shift;; esac; shift; done
"$QC_TOOLS/loop-state.sh" is-clean || die "no clean full iteration yet: pull requests are opened only after one"
OWN=$(cfg get repos.user_owner); BASE=$(cfg get repos.upstream.base_branch)
for r in $REPOS; do up=$(repo_upstream "$r"); mine=$(repo_url "$r" | sed -E 's#^https://github.com/##; s#\.git$##')
	gls --heads "$(repo_url "$r")" "$BR" | grep -q . || die "$r: $BR is not pushed to your repo"
	if [ "$(echo "$mine" | tr A-Z a-z)" = "$(echo "$up" | tr A-Z a-z)" ]; then head=$BR; else head=$OWN:$BR; fi
	J=$(mktemp "$QC_STATE/tmp/pr.XXXXXX"); python3 -I - "$J" "$TITLE" "$head" "$BASE" "${BODY:-}" "$("$QC_TOOLS/loop-state.sh" show)" <<'PY'
import json,sys
f,t,h,b,bf,ls=sys.argv[1:7]
body=open(bf).read() if bf else "Opened by the TopStor QC agent after one full QualityCheck iteration passed with no code change.\n\nLoop state: "+ls
json.dump({"title":t,"head":h,"base":b,"body":body,"maintainer_can_modify":True},open(f,"w"))
PY
	if [ -n "${DRYRUN:-}" ]; then echo "DRYRUN: POST repos/$up/pulls $(cat "$J")"; rm -f "$J"; continue; fi
	O=$(gh_api POST "repos/$up/pulls" "$J"); rm -f "$J"
	url=$(echo "$O" | python3 -I -c 'import sys,json;print(json.load(sys.stdin).get("html_url",""))' 2>/dev/null)
	if [ -z "$url" ]; then url=$(gh_api GET "repos/$up/pulls?head=${mine%%/*}:$BR&state=open" | python3 -I -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["html_url"] if d else "")' 2>/dev/null)
		[ -n "$url" ] && echo "$r: PR already open: $url" || echo "$r: PR FAILED: $(echo "$O" | mask | cut -c1-300)"
	else echo "$r: PR opened: $url"; fi
done
